function Test-CshMeaningfulUserText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $false
    }

    $clean = ($Text -replace '\s+', ' ').Trim()
    if ($clean.Length -lt 12) {
        return $false
    }

    $ignorePrefixes = @(
        '<environment_context>'
        '# AGENTS.md'
        'AGENTS.md'
    )

    foreach ($prefix in $ignorePrefixes) {
        if ($clean.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
    }

    if ($clean -match '^\s*<\w+') {
        return $false
    }

    return $true
}

function Get-CshPreviewCandidate {
    param([object]$Entry)

    if ($Entry.type -eq 'event_msg' -and $Entry.payload.type -eq 'user_message' -and $Entry.payload.message) {
        return [string]$Entry.payload.message
    }

    if ($Entry.type -eq 'response_item' -and $Entry.payload.type -eq 'message' -and $Entry.payload.role -eq 'user') {
        foreach ($contentItem in $Entry.payload.content) {
            if ($contentItem.type -eq 'input_text' -and $contentItem.text) {
                return [string]$contentItem.text
            }
        }
    }

    return ''
}

function Get-CshBranchDisplay {
    param(
        [string]$BranchName,
        [bool]$IsDetachedHead
    )

    if (-not [string]::IsNullOrWhiteSpace($BranchName)) {
        return $BranchName.Trim()
    }

    if ($IsDetachedHead) {
        return 'detached'
    }

    return ''
}

function Get-CshWorkspaceKey {
    param(
        [string]$RepoRoot,
        [string]$BranchName,
        [string]$ProjectPath
    )

    $parts = foreach ($value in @($RepoRoot, $BranchName, $ProjectPath)) {
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $value.Trim().ToLowerInvariant()
        }
    }

    if (@($parts).Count -eq 0) {
        return ''
    }

    return (@($parts) -join '|')
}

function Get-CshDisplayGroupKey {
    param([Parameter(Mandatory = $true)][object]$Session)

    if (-not [string]::IsNullOrWhiteSpace([string]$Session.WorkspaceKey)) {
        return [string]$Session.WorkspaceKey
    }

    return [string]$Session.ProjectKey
}

function Get-CshWorkspaceLabel {
    param(
        [string]$RepoName,
        [string]$BranchDisplay,
        [string]$ProjectName,
        [string]$ProjectPath,
        [string]$RepoRoot
    )

    if ([string]::IsNullOrWhiteSpace($RepoName)) {
        return $ProjectName
    }

    $label = $RepoName
    if (-not [string]::IsNullOrWhiteSpace($BranchDisplay)) {
        $label = '{0} @ {1}' -f $label, $BranchDisplay
    }

    if (-not [string]::IsNullOrWhiteSpace($ProjectPath) -and -not [string]::IsNullOrWhiteSpace($RepoRoot)) {
        $normalizedProjectPath = Normalize-CshPath $ProjectPath
        $normalizedRepoRoot = Normalize-CshPath $RepoRoot
        if ($normalizedProjectPath -and $normalizedRepoRoot -and ($normalizedProjectPath -ne $normalizedRepoRoot)) {
            $leaf = Get-CshProjectName -ProjectPath $normalizedProjectPath
            if (-not [string]::IsNullOrWhiteSpace($leaf) -and ($leaf -ne $RepoName)) {
                $label = '{0} / {1}' -f $label, $leaf
            }
        }
    }

    return $label
}

function Get-CshGitContext {
    param(
        [string]$Path,
        [hashtable]$Cache
    )

    $normalizedPath = Normalize-CshPath $Path
    $defaultWorkspaceKey = if ([string]::IsNullOrWhiteSpace($normalizedPath)) { '' } else { $normalizedPath.ToLowerInvariant() }
    $emptyContext = [pscustomobject]@{
        RepoRoot       = ''
        RepoName       = ''
        BranchName     = ''
        BranchDisplay  = ''
        IsDetachedHead = $false
        WorkspaceKey   = $defaultWorkspaceKey
    }

    if ([string]::IsNullOrWhiteSpace($normalizedPath)) {
        return $emptyContext
    }

    if ($Cache -and $Cache.ContainsKey($normalizedPath)) {
        return $Cache[$normalizedPath]
    }

    $context = $emptyContext
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git -and (Test-Path -LiteralPath $normalizedPath)) {
        try {
            $repoRootOutput = & $git.Source -C $normalizedPath rev-parse --show-toplevel 2>$null
            if ($LASTEXITCODE -eq 0 -and $repoRootOutput) {
                $repoRoot = Normalize-CshPath ([string]($repoRootOutput | Select-Object -First 1))
                $branchOutput = & $git.Source -C $normalizedPath branch --show-current 2>$null
                $branchName = if ($LASTEXITCODE -eq 0 -and $branchOutput) { [string]($branchOutput | Select-Object -First 1) } else { '' }
                $branchName = $branchName.Trim()
                $branchDisplay = Get-CshBranchDisplay -BranchName $branchName -IsDetachedHead ([string]::IsNullOrWhiteSpace($branchName))

                $context = [pscustomobject]@{
                    RepoRoot       = $repoRoot
                    RepoName       = Get-CshProjectName -ProjectPath $repoRoot
                    BranchName     = $branchName
                    BranchDisplay  = $branchDisplay
                    IsDetachedHead = [string]::IsNullOrWhiteSpace($branchName)
                    WorkspaceKey   = Get-CshWorkspaceKey -RepoRoot $repoRoot -BranchName $branchDisplay -ProjectPath $normalizedPath
                }
            }
        } catch {
            $context = $emptyContext
        }
    }

    if ($Cache) {
        $Cache[$normalizedPath] = $context
    }

    return $context
}

function Read-CshSessionFile {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$File,
        [Parameter(Mandatory = $true)][hashtable]$Index,
        [hashtable]$GitContextCache
    )

    $meta = $null
    $preview = ''
    $fallbackPreview = ''
    $stream = $null
    $reader = $null

    try {
        $stream = [System.IO.File]::Open($File.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = [System.IO.StreamReader]::new($stream)

        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            try {
                $entry = $line | ConvertFrom-Json -Depth 20
            } catch {
                continue
            }

            if (-not $meta -and $entry.type -eq 'session_meta') {
                $meta = $entry.payload
            }

            $candidate = Get-CshPreviewCandidate -Entry $entry
            if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                if ([string]::IsNullOrWhiteSpace($fallbackPreview)) {
                    $fallbackPreview = $candidate
                }

                if ((-not $preview) -and (Test-CshMeaningfulUserText -Text $candidate)) {
                    $preview = $candidate
                }
            }

            if ($meta -and $preview) {
                break
            }
        }
    } finally {
        if ($reader) {
            $reader.Dispose()
        }
        if ($stream) {
            $stream.Dispose()
        }
    }

    if (-not $meta -or -not $meta.id) {
        return $null
    }

    $timestamp = $null
    if ($meta.timestamp) {
        try {
            $timestamp = [datetimeoffset]::Parse([string]$meta.timestamp)
        } catch {
            $timestamp = $null
        }
    }

    if (-not $timestamp) {
        $timestamp = [datetimeoffset]$File.LastWriteTimeUtc
    }

    if (-not $preview) {
        $preview = $fallbackPreview
    }

    $projectPath = Normalize-CshPath ([string]$meta.cwd)
    $alias = Get-CshAlias -Index $Index -SessionId ([string]$meta.id)
    $gitContext = Get-CshGitContext -Path $projectPath -Cache $GitContextCache
    $previewText = Compress-CshText -Text $preview -MaxLength 160
    $displayTitle = if ($alias) { $alias } elseif ($previewText) { $previewText } else { 'Session {0}' -f $meta.id }

    return [pscustomobject]@{
        SessionId         = [string]$meta.id
        Timestamp         = $timestamp
        TimestampText     = Format-CshTimestamp -Timestamp $timestamp
        LastUpdated       = [datetimeoffset]$File.LastWriteTimeUtc
        LastUpdatedText   = Format-CshTimestamp -Timestamp ([datetimeoffset]$File.LastWriteTimeUtc)
        LastUpdatedAge    = Format-CshRelativeAge -Timestamp ([datetimeoffset]$File.LastWriteTimeUtc)
        ProjectPath       = $projectPath
        ProjectKey        = $projectPath.ToLowerInvariant()
        ProjectName       = Get-CshProjectName -ProjectPath $projectPath
        RepoRoot          = $gitContext.RepoRoot
        RepoName          = $gitContext.RepoName
        BranchName        = $gitContext.BranchName
        BranchDisplay     = $gitContext.BranchDisplay
        IsDetachedHead    = $gitContext.IsDetachedHead
        WorkspaceKey      = $gitContext.WorkspaceKey
        WorkspaceLabel    = Get-CshWorkspaceLabel -RepoName $gitContext.RepoName -BranchDisplay $gitContext.BranchDisplay -ProjectName (Get-CshProjectName -ProjectPath $projectPath) -ProjectPath $projectPath -RepoRoot $gitContext.RepoRoot
        FilePath          = $File.FullName
        ProjectExists     = [bool](Test-Path $projectPath)
        Alias             = $alias
        Preview           = $previewText
        DisplayTitle      = $displayTitle
    }
}

function Get-CshSessions {
    param([hashtable]$Index = $(Get-CshIndex))

    $sessionRoot = Get-CshSessionRoot
    if (-not (Test-Path $sessionRoot)) {
        return @()
    }

    $files = Get-ChildItem -Path $sessionRoot -Recurse -File -Filter '*.jsonl' | Sort-Object LastWriteTime -Descending
    $gitContextCache = @{}
    $sessions = foreach ($file in $files) {
        $session = Read-CshSessionFile -File $file -Index $Index -GitContextCache $gitContextCache
        if ($session) {
            $session
        }
    }

    return @($sessions | Sort-Object @{ Expression = 'Timestamp'; Descending = $true }, @{ Expression = 'ProjectPath'; Descending = $false })
}

function Get-CshDisplaySessions {
    param([Parameter(Mandatory = $true)][object[]]$Sessions)

    $groups = $Sessions | Group-Object { Get-CshDisplayGroupKey -Session $_ }
    $orderedProjects = foreach ($group in $groups) {
        $items = @($group.Group | Sort-Object @{ Expression = 'Timestamp'; Descending = $true })
        [pscustomobject]@{
            GroupKey       = Get-CshDisplayGroupKey -Session $items[0]
            WorkspaceLabel = if (-not [string]::IsNullOrWhiteSpace([string]$items[0].WorkspaceLabel)) { $items[0].WorkspaceLabel } else { $items[0].ProjectName }
            ProjectPath    = $items[0].ProjectPath
            LatestTime     = $items[0].Timestamp
            Items          = $items
        }
    }

    $display = New-Object 'System.Collections.Generic.List[object]'
    foreach ($project in ($orderedProjects | Sort-Object @{ Expression = 'LatestTime'; Descending = $true }, @{ Expression = 'ProjectPath'; Descending = $false })) {
        foreach ($session in $project.Items) {
            $displayNumber = $display.Count + 1
            [void]$display.Add([pscustomobject]@{
                SessionId       = $session.SessionId
                DisplayNumber   = $displayNumber
                Timestamp       = $session.Timestamp
                TimestampText   = $session.TimestampText
                LastUpdated     = $session.LastUpdated
                LastUpdatedText = $session.LastUpdatedText
                LastUpdatedAge  = $session.LastUpdatedAge
                ProjectPath     = $session.ProjectPath
                ProjectKey      = $session.ProjectKey
                ProjectName     = $session.ProjectName
                GroupKey        = $project.GroupKey
                RepoRoot        = $session.RepoRoot
                RepoName        = $session.RepoName
                BranchName      = $session.BranchName
                BranchDisplay   = $session.BranchDisplay
                IsDetachedHead  = $session.IsDetachedHead
                WorkspaceKey    = $session.WorkspaceKey
                WorkspaceLabel  = if (-not [string]::IsNullOrWhiteSpace([string]$session.WorkspaceLabel)) { $session.WorkspaceLabel } else { $project.WorkspaceLabel }
                FilePath        = $session.FilePath
                ProjectExists   = $session.ProjectExists
                Alias           = $session.Alias
                Preview         = $session.Preview
                DisplayTitle    = $session.DisplayTitle
            })
        }
    }

    return $display.ToArray()
}

function Get-CshFilteredDisplaySessions {
    param(
        [Parameter(Mandatory = $true)][object[]]$Sessions,
        [string]$Query
    )

    $displaySessions = @(Get-CshDisplaySessions -Sessions $Sessions)
    $normalizedQuery = if ($null -eq $Query) { '' } else { [string]$Query }
    $normalizedQuery = $normalizedQuery.Trim()
    if ($normalizedQuery -match '^[\s"]*$') {
        $normalizedQuery = ''
    }

    if ([string]::IsNullOrWhiteSpace($normalizedQuery)) {
        return $displaySessions
    }

    $trimmedQuery = $normalizedQuery
    if ($trimmedQuery -match '^\d+$') {
        return @($displaySessions | Where-Object {
            [string]$_.DisplayNumber -like "$trimmedQuery*"
        })
    }

    $searchTitles = $false
    $searchRepos = $false
    $searchBranches = $false
    $textQuery = $trimmedQuery
    if ($trimmedQuery -match '^(t:|title:)\s*(.+)$') {
        $searchTitles = $true
        $textQuery = $Matches[2].Trim()
    } elseif ($trimmedQuery -match '^(r:|repo:)\s*(.+)$') {
        $searchRepos = $true
        $textQuery = $Matches[2].Trim()
    } elseif ($trimmedQuery -match '^(b:|branch:)\s*(.+)$') {
        $searchBranches = $true
        $textQuery = $Matches[2].Trim()
    }

    if ([string]::IsNullOrWhiteSpace($textQuery)) {
        return $displaySessions
    }

    $lowerQuery = $textQuery.ToLowerInvariant()
    if ($searchTitles) {
        return @($displaySessions | Where-Object {
            $_.DisplayTitle.ToLowerInvariant().Contains($lowerQuery)
        })
    }

    if ($searchRepos) {
        return @($displaySessions | Where-Object {
            ([string]$_.RepoName).ToLowerInvariant().Contains($lowerQuery)
        })
    }

    if ($searchBranches) {
        return @($displaySessions | Where-Object {
            ([string]$_.BranchDisplay).ToLowerInvariant().Contains($lowerQuery)
        })
    }

    return @($displaySessions | Where-Object {
        $_.ProjectName.ToLowerInvariant().Contains($lowerQuery) -or
        ([string]$_.RepoName).ToLowerInvariant().Contains($lowerQuery)
    })
}

function Find-CshSession {
    param(
        [Parameter(Mandatory = $true)][object[]]$Sessions,
        [Parameter(Mandatory = $true)][string]$SessionId
    )

    $exact = @($Sessions | Where-Object { $_.SessionId -eq $SessionId })
    if ($exact.Count -eq 1) {
        return $exact[0]
    }

    $prefix = @($Sessions | Where-Object { $_.SessionId -like "$SessionId*" })
    if ($prefix.Count -eq 1) {
        return $prefix[0]
    }

    return $null
}

param(
    [string]$Repository = 'vinzify/Codex-Session-Hub',
    [string]$Ref = 'master',
    [string]$InstallRoot,
    [switch]$SkipShellIntegration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CshDefaultInstallRoot {
    if ($IsWindows) {
        return (Join-Path $env:LOCALAPPDATA 'CodexSessionHub')
    }

    return (Join-Path $HOME '.local/share/codex-session-hub')
}

function Get-CshDefaultFzfHelp {
    if ($IsWindows) {
        return 'winget install junegunn.fzf'
    }

    if ($IsMacOS) {
        return 'brew install fzf'
    }

    return 'Install fzf with your distro package manager, for example: apt install fzf'
}

function Test-CshRepoRoot {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Test-Path (Join-Path $Path 'src/CodexSessionHub.psd1')) -and (Test-Path (Join-Path $Path 'bin/csx.ps1'))
}

function Resolve-CshSourceRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Ref
    )

    $scriptPath = ''

    $psCommandPathVariable = Get-Variable -Name PSCommandPath -Scope Script -ErrorAction SilentlyContinue
    if ($psCommandPathVariable -and -not [string]::IsNullOrWhiteSpace([string]$psCommandPathVariable.Value)) {
        $scriptPath = [string]$psCommandPathVariable.Value
    }

    if ([string]::IsNullOrWhiteSpace($scriptPath) -and $MyInvocation -and $MyInvocation.MyCommand) {
        $pathProperty = $MyInvocation.MyCommand.PSObject.Properties['Path']
        if ($pathProperty -and -not [string]::IsNullOrWhiteSpace([string]$pathProperty.Value)) {
            $scriptPath = [string]$pathProperty.Value
        }
    }

    $localRoot = ''
    if (-not [string]::IsNullOrWhiteSpace($scriptPath)) {
        $localRoot = Split-Path -Parent $scriptPath
    }

    if (-not [string]::IsNullOrWhiteSpace($localRoot) -and (Test-CshRepoRoot -Path $localRoot)) {
        return [pscustomobject]@{
            Root        = $localRoot
            Temporary   = $false
            Description = "local source at $localRoot"
        }
    }

    $archiveUrl = "https://github.com/$Repository/archive/refs/heads/$Ref.zip"
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('codex-session-hub-install-' + [guid]::NewGuid().ToString('N'))
    $archivePath = Join-Path $tempRoot 'source.zip'
    $extractRoot = Join-Path $tempRoot 'extract'

    New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

    Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath
    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractRoot -Force

    $repoRoot = Get-ChildItem -Path $extractRoot -Directory | Select-Object -First 1
    if (-not $repoRoot -or -not (Test-CshRepoRoot -Path $repoRoot.FullName)) {
        throw "Unable to locate Codex Session Hub sources in downloaded archive: $archiveUrl"
    }

    return [pscustomobject]@{
        Root        = $repoRoot.FullName
        Temporary   = $true
        TempRoot    = $tempRoot
        Description = "downloaded archive from $archiveUrl"
    }
}

function Install-CshPayload {
    param(
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    if (Test-Path $DestinationRoot) {
        Remove-Item -LiteralPath $DestinationRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Force -Path $DestinationRoot | Out-Null

    foreach ($relativePath in @('bin', 'src', 'README.md', 'LICENSE', 'CHANGELOG.md', 'install.ps1', 'uninstall.ps1')) {
        $sourcePath = Join-Path $SourceRoot $relativePath
        if (-not (Test-Path $sourcePath)) {
            throw "Required install asset is missing: $sourcePath"
        }

        Copy-Item -Path $sourcePath -Destination (Join-Path $DestinationRoot $relativePath) -Recurse -Force
    }
}

function Install-CshShellIntegration {
    param([Parameter(Mandatory = $true)][string]$InstalledRoot)

    $profilePath = $PROFILE.CurrentUserCurrentHost
    $profileDirectory = Split-Path -Parent $profilePath
    if (-not (Test-Path $profileDirectory)) {
        New-Item -ItemType Directory -Force -Path $profileDirectory | Out-Null
    }

    $modulePath = (Join-Path $InstalledRoot 'src/CodexSessionHub.psd1').Replace("'", "''")
    $markerStart = '# >>> Codex Session Hub >>>'
    $markerEnd = '# <<< Codex Session Hub <<<'
    $blockTemplate = @'
# >>> Codex Session Hub >>>
$cshFzfPath = Join-Path $env:LOCALAPPDATA 'Programs\fzf\bin'
if ((Test-Path $cshFzfPath) -and (($env:Path -split ';') -notcontains $cshFzfPath)) {
    $env:Path = "$cshFzfPath;$env:Path"
}
function csx {
    Import-Module '{0}' -Force
    Invoke-CsxCli -Arguments $args -ShellMode
}
Set-Alias cxs csx
# <<< Codex Session Hub <<<
'@
    $block = $blockTemplate -f $modulePath

    $content = if (Test-Path $profilePath) { Get-Content -Path $profilePath -Raw } else { '' }
    $pattern = [regex]::Escape($markerStart) + '.*?' + [regex]::Escape($markerEnd)

    if ($content -match $pattern) {
        $updated = [regex]::Replace($content, $pattern, $block, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    } elseif ([string]::IsNullOrWhiteSpace($content)) {
        $updated = $block
    } else {
        $updated = $content.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $block
    }

    Set-Content -Path $profilePath -Value $updated
    return $profilePath
}

function Get-CshPostInstallState {
    param(
        [Parameter(Mandatory = $true)][string]$InstalledRoot,
        [bool]$ProfileInstalled
    )

    $profilePath = $PROFILE.CurrentUserCurrentHost
    $modulePath = Join-Path $InstalledRoot 'src/CodexSessionHub.psd1'

    [pscustomobject]@{
        ModulePath       = $modulePath
        ProfilePath      = $profilePath
        ProfileInstalled = $ProfileInstalled
        FzfAvailable     = [bool](Get-Command fzf -ErrorAction SilentlyContinue)
        CodexAvailable   = [bool](Get-Command codex -ErrorAction SilentlyContinue)
    }
}

$resolvedInstallRoot = if ($InstallRoot) { $InstallRoot } else { Get-CshDefaultInstallRoot }
$source = $null

try {
    $source = Resolve-CshSourceRoot -Repository $Repository -Ref $Ref
    Install-CshPayload -SourceRoot $source.Root -DestinationRoot $resolvedInstallRoot
    $profileInstalled = $false
    if (-not $SkipShellIntegration) {
        [void](Install-CshShellIntegration -InstalledRoot $resolvedInstallRoot)
        $profileInstalled = $true
    }
    $postInstall = Get-CshPostInstallState -InstalledRoot $resolvedInstallRoot -ProfileInstalled $profileInstalled

    Write-Host "Installed Codex Session Hub to $resolvedInstallRoot"
    Write-Host "Source: $($source.Description)"

    if (-not $postInstall.FzfAvailable) {
        Write-Warning "fzf was not found in PATH. Install it with: $(Get-CshDefaultFzfHelp)"
    }

    if (-not $postInstall.CodexAvailable) {
        Write-Warning 'codex was not found in PATH. Install Codex CLI before using csx.'
    }

    if (-not $SkipShellIntegration) {
        Write-Host "Shell integration installed in $($postInstall.ProfilePath)"
        Write-Host 'Reload your shell with: . $PROFILE'
        Write-Host 'Then run: csx doctor'
    } else {
        Write-Host 'Shell integration was skipped.'
    }
} finally {
    if ($source -and $source.Temporary -and (Test-Path $source.TempRoot)) {
        Remove-Item -LiteralPath $source.TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

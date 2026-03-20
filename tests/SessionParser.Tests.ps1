$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $here
Import-Module (Join-Path $projectRoot 'src/CodexSessionHub.psd1') -Force
$module = Get-Module CodexSessionHub

function Invoke-CshInModule {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList
    )

    & $module.NewBoundScriptBlock($ScriptBlock) @ArgumentList
}

Describe 'Normalize-CshPath' {
    It 'removes the Windows long path prefix' {
        (Invoke-CshInModule -ScriptBlock { Normalize-CshPath '\\?\D:\code\example' }) | Should Be 'D:\code\example'
    }
}

Describe 'Get-CshFilteredDisplaySessions' {
    It 'treats quote-only queries as empty' {
        $sessions = @(
            [pscustomobject]@{
                SessionId='1'; Timestamp=[datetimeoffset]'2026-03-02'; TimestampText='2026-03-02 00:00'
                LastUpdated=[datetimeoffset]'2026-03-02'; LastUpdatedText='2026-03-02 00:00'; LastUpdatedAge='1h ago'
                ProjectKey='desktop'; ProjectName='Desktop'; ProjectPath='C:\Users\twinr\Desktop'; FilePath=''
                ProjectExists=$true; Alias=''; Preview='Preview'; DisplayTitle='Title'
            }
        )

        $filtered = @(Invoke-CshInModule -ScriptBlock {
            param($inputSessions)
            Get-CshFilteredDisplaySessions -Sessions $inputSessions -Query '""""'
        } -ArgumentList (, $sessions))
        $filtered.Count | Should Be 1
        $filtered[0].SessionId | Should Be '1'
    }
}

Describe 'Format-CshAsciiBanner' {
    It 'renders a compact three-line banner' {
        $banner = Invoke-CshInModule -ScriptBlock { Format-CshAsciiBanner -Kind 'project' -Primary 'Desktop' -Secondary '10 sessions' }
        $lines = @($banner -split [Environment]::NewLine)

        $lines.Count | Should Be 3
        $lines[1] | Should Match 'PROJECT'
        $lines[1] | Should Match 'Desktop'
    }
}

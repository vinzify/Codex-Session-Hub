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

Describe 'Index metadata' {
    It 'stores aliases in memory' {
        $index = Invoke-CshInModule -ScriptBlock { New-CshIndex }
        Invoke-CshInModule -ScriptBlock {
            param($sharedIndex)
            Set-CshAlias -Index $sharedIndex -SessionId 'abc' -Alias 'hello'
        } -ArgumentList $index
        (Invoke-CshInModule -ScriptBlock {
            param($sharedIndex)
            Get-CshAlias -Index $sharedIndex -SessionId 'abc'
        } -ArgumentList $index) | Should Be 'hello'
    }

    It 'clears aliases when set to blank' {
        $index = Invoke-CshInModule -ScriptBlock { New-CshIndex }
        Invoke-CshInModule -ScriptBlock {
            param($sharedIndex)
            Set-CshAlias -Index $sharedIndex -SessionId 'abc' -Alias 'hello'
            Set-CshAlias -Index $sharedIndex -SessionId 'abc' -Alias ''
        } -ArgumentList $index

        (Invoke-CshInModule -ScriptBlock {
            param($sharedIndex)
            Get-CshAlias -Index $sharedIndex -SessionId 'abc'
        } -ArgumentList $index) | Should Be ''
    }

    It 'removes alias entries when cleared' {
        $index = Invoke-CshInModule -ScriptBlock { New-CshIndex }
        Invoke-CshInModule -ScriptBlock {
            param($sharedIndex)
            Set-CshAlias -Index $sharedIndex -SessionId 'abc' -Alias 'hello'
            Set-CshAlias -Index $sharedIndex -SessionId 'abc' -Alias ''
        } -ArgumentList $index

        $index.sessions.ContainsKey('abc') | Should Be $false
    }
}

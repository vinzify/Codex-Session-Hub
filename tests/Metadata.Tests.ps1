$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $here
$modulePath = Join-Path $projectRoot 'src/CodexSessionHub.psd1'

Describe 'Index metadata' {
    It 'stores aliases in memory' {
        $module = Import-Module $modulePath -Force -PassThru
        $bound = $module.NewBoundScriptBlock({ New-CshIndex })
        $index = & $bound
        $bound = $module.NewBoundScriptBlock({
            param($sharedIndex)
            Set-CshAlias -Index $sharedIndex -SessionId 'abc' -Alias 'hello'
        })
        & $bound $index
        $bound = $module.NewBoundScriptBlock({
            param($sharedIndex)
            Get-CshAlias -Index $sharedIndex -SessionId 'abc'
        })
        (& $bound $index) | Should Be 'hello'
    }

    It 'clears aliases when set to blank' {
        $module = Import-Module $modulePath -Force -PassThru
        $bound = $module.NewBoundScriptBlock({ New-CshIndex })
        $index = & $bound
        $bound = $module.NewBoundScriptBlock({
            param($sharedIndex)
            Set-CshAlias -Index $sharedIndex -SessionId 'abc' -Alias 'hello'
            Set-CshAlias -Index $sharedIndex -SessionId 'abc' -Alias ''
        })
        & $bound $index

        $bound = $module.NewBoundScriptBlock({
            param($sharedIndex)
            Get-CshAlias -Index $sharedIndex -SessionId 'abc'
        })
        (& $bound $index) | Should Be ''
    }

    It 'removes alias entries when cleared' {
        $module = Import-Module $modulePath -Force -PassThru
        $bound = $module.NewBoundScriptBlock({ New-CshIndex })
        $index = & $bound
        $bound = $module.NewBoundScriptBlock({
            param($sharedIndex)
            Set-CshAlias -Index $sharedIndex -SessionId 'abc' -Alias 'hello'
            Set-CshAlias -Index $sharedIndex -SessionId 'abc' -Alias ''
        })
        & $bound $index

        $index.sessions.ContainsKey('abc') | Should Be $false
    }
}

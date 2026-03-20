Describe 'install.ps1 bootstrap mode' {
    It 'supports fileless scriptblock execution' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $installScriptPath = Join-Path $projectRoot 'install.ps1'
        $installRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('csh-install-test-' + [guid]::NewGuid().ToString('N'))

        try {
            $scriptContent = Get-Content -Path $installScriptPath -Raw
            & ([scriptblock]::Create($scriptContent)) -InstallRoot $installRoot -SkipShellIntegration *> $null

            (Test-Path (Join-Path $installRoot 'src/CodexSessionHub.psd1')) | Should -BeTrue
            (Test-Path (Join-Path $installRoot 'bin/csx.ps1')) | Should -BeTrue
            (Test-Path (Join-Path $installRoot 'README.md')) | Should -BeTrue
        }
        finally {
            if (Test-Path $installRoot) {
                Remove-Item -LiteralPath $installRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'defines shell integration as a literal template' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $installScriptPath = Join-Path $projectRoot 'install.ps1'
        $scriptContent = Get-Content -Path $installScriptPath -Raw

        $scriptContent | Should -Match '\$blockTemplate = @'''
        $scriptContent | Should -Match "Join-Path [`$]env:LOCALAPPDATA 'Programs\\fzf\\bin'"
        $scriptContent | Should -Match 'Invoke-CsxCli -Arguments \$args -ShellMode'
        $scriptContent | Should -Match '\$block = \$blockTemplate -f \$modulePath'
        $scriptContent | Should -Match 'if \(\(Test-Path \$cshFzfPath\).*\)\) \{\{'
        $scriptContent | Should -Match 'function csx \{\{'
    }

    It 'formats the shell integration template successfully' {
        $projectRoot = Split-Path -Parent $PSScriptRoot
        $installScriptPath = Join-Path $projectRoot 'install.ps1'
        $scriptContent = Get-Content -Path $installScriptPath -Raw
        $templateMatch = [regex]::Match($scriptContent, "(?s)\$blockTemplate = @'`r?`n(.*?)`r?`n'@")

        $templateMatch.Success | Should -BeTrue

        $formatted = $templateMatch.Groups[1].Value -f 'C:\Temp\CodexSessionHub\src\CodexSessionHub.psd1'
        $formatted | Should -Match 'function csx \{'
        $formatted | Should -Match "Import-Module 'C:\\Temp\\CodexSessionHub\\src\\CodexSessionHub\.psd1' -Force"
    }
}

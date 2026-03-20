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
}

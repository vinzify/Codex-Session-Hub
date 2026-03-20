param(
    [string]$InstallRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CshDefaultInstallRoot {
    if ($IsWindows) {
        return (Join-Path $env:LOCALAPPDATA 'CodexSessionHub')
    }

    return (Join-Path $HOME '.local/share/codex-session-hub')
}

function Get-CshProfilePath {
    return $PROFILE.CurrentUserCurrentHost
}

function Uninstall-CshShellIntegration {
    $profilePath = Get-CshProfilePath
    if (-not (Test-Path $profilePath)) {
        return
    }

    $markerStart = '# >>> Codex Session Hub >>>'
    $markerEnd = '# <<< Codex Session Hub <<<'
    $content = Get-Content -Path $profilePath -Raw
    $pattern = [regex]::Escape($markerStart) + '.*?' + [regex]::Escape($markerEnd)
    $updated = [regex]::Replace($content, $pattern, '', [System.Text.RegularExpressions.RegexOptions]::Singleline).Trim()

    if ($updated) {
        Set-Content -Path $profilePath -Value ($updated + [Environment]::NewLine)
    } else {
        Remove-Item -Path $profilePath -Force
    }
}

$resolvedInstallRoot = if ($InstallRoot) { $InstallRoot } else { Get-CshDefaultInstallRoot }

Uninstall-CshShellIntegration

if (Test-Path $resolvedInstallRoot) {
    Remove-Item -LiteralPath $resolvedInstallRoot -Recurse -Force
    Write-Host "Removed Codex Session Hub from $resolvedInstallRoot"
} else {
    Write-Host "Install root not found at $resolvedInstallRoot"
}

Write-Host 'Reload your shell with: . $PROFILE'

# Install Guide

## Recommended

Once the GitHub repository is public:

```powershell
irm https://raw.githubusercontent.com/vinzify/Codex-Session-Hub/master/install.ps1 | iex
```

Then reload your shell:

```powershell
. $PROFILE
csx doctor
```

## Requirements

1. Install PowerShell 7.
2. Install `fzf`.
3. Make sure `codex` is available in `PATH`.

## From Source

1. Clone the repo.
2. Run `pwsh -File .\install.ps1`.
3. Reload your shell with `. $PROFILE`.

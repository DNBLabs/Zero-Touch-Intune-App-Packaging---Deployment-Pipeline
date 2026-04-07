# Zero-Touch Intune App Packaging & Deployment Pipeline

Convention-over-configuration **PowerShell 7** pipeline: drop an allowlisted `.msi` or `.exe` into `inbox/`, produce a `.intunewin` with Microsoft’s **Win32 Content Prep Tool**, then publish and assign a Win32 app in **Microsoft Intune** via **Microsoft Graph** (lab / portfolio scope).

## Status

**Task 2** — `IntuneDropPipeline` PowerShell module ships `Get-IntuneDropConfiguration` and `Write-IntuneDropLog`. Run tests: `Invoke-Pester .\tests -Output Detailed` from the repo root. Entry scripts (`Process-Inbox.ps1`, `Watch-Inbox.ps1`) come in later tasks.

## Documentation

| Document | Purpose |
|----------|---------|
| [docs/SPEC.md](docs/SPEC.md) | Requirements, commands, boundaries, success criteria |
| [docs/IMPLEMENTATION-PLAN.md](docs/IMPLEMENTATION-PLAN.md) | Dependency order, tasks, checkpoints |
| [docs/ideas/drop-folder-intune-convention.md](docs/ideas/drop-folder-intune-convention.md) | Original concept one-pager |

## Quick start (after implementation is complete)

Prerequisites will include **PowerShell 7+**, the **Microsoft.Graph** modules, locally installed **IntuneWinAppUtil.exe**, and an **Azure AD app registration** with appropriate Graph permissions. Follow `docs/SPEC.md` for exact commands; until `src/` exists, there is nothing to run beyond validating this scaffold.

## Configuration

1. Copy `.env.example` to `.env`.
2. Set `INTUNE_DROP_PREP_TOOL_EXE` and Graph-related variables. See [tools/README.md](tools/README.md) for where to place the packaging tool.
3. Optionally add **`config.local.json`** at the repo root (listed in `.gitignore` — do not commit) to override **path** keys only: `INTUNE_DROP_INBOX_PATH`, `INTUNE_DROP_DONE_PATH`, `INTUNE_DROP_FAILED_PATH`, `INTUNE_DROP_STAGING_PATH`. Process environment variables override those JSON values when both are set.
4. Never commit `.env` or real secrets.

Load the module after setting process env (for example by dot-sourcing `.env` in your shell, or exporting variables manually):

```powershell
Import-Module .\src\Modules\IntuneDropPipeline\IntuneDropPipeline.psd1 -Force
Get-IntuneDropConfiguration
```

## Layout

```text
inbox/       # Drop allowlisted installers here (tracked empty via .gitkeep)
staging/     # Created at runtime; gitignored
done/        # Successfully processed files; gitignored
failed/      # Rejected files; gitignored
tools/       # Readme only — place IntuneWinAppUtil locally, do not commit it
docs/        # Specs and plans
```

# Zero-Touch Intune App Packaging & Deployment Pipeline

Convention-over-configuration **PowerShell 7** pipeline: drop an allowlisted `.msi` or `.exe` into `inbox/`, produce a `.intunewin` with Microsoft’s **Win32 Content Prep Tool**, then publish and assign a Win32 app in **Microsoft Intune** via **Microsoft Graph** (lab / portfolio scope).

## Status

**Task 5** — `Get-IntuneDropMsiProductCode` reads **ProductCode** from an `.msi` via **Windows Installer COM** (Windows only; `ERR_MSI_METADATA` on failure). Optional integration test: set `INTUNE_DROP_TEST_MSI_PATH` to a real MSI, then `Invoke-Pester .\tests`. Entry scripts arrive in later tasks.

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

## Filename convention

Installers in `inbox/` must be named:

`Vendor_AppName_x.y.z.msi` or `Vendor_AppName_x.y.z.exe`

- **Vendor** and **AppName** cannot contain underscores (one segment each).
- **Version** is two to four numeric segments (examples: `1.0`, `1.2.3`, `1.2.3.4`).
- Parse at runtime with: `Get-IntuneDropPackageFromFileName` (from the module).

## Allowlist (v1)

Committed rows live in **`src/Modules/IntuneDropPipeline/Data/IntuneDropAllowlist.json`**. Extend this file when you add real demo apps; do not invent silent switches for unknown vendors.

| Row id | Extension | Install (summary) | Notes |
|--------|-----------|-------------------|--------|
| `portfolio-msi-v1` | `msi` | `msiexec /i "<file>" /qn /norestart` | Uninstall/detection use MSI **product code** from `Get-IntuneDropMsiProductCode -Path '<full path to msi>'` (Windows + COM only). |
| `portfolio-inno-style-exe-v1` | `exe` | `"<file>" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART` | Example **Inno-style** flags; file detection path is `%ProgramFiles%\<Vendor>\<AppName>\<AppName>.exe` — adjust the JSON if your EXE installs elsewhere. |

Resolve intent: `Get-IntuneDropInstallIntent -Package (Get-IntuneDropPackageFromFileName -FileName '...')`.

## Layout

```text
inbox/       # Drop allowlisted installers here (tracked empty via .gitkeep)
staging/     # Created at runtime; gitignored
done/        # Successfully processed files; gitignored
failed/      # Rejected files; gitignored
tools/       # Readme only — place IntuneWinAppUtil locally, do not commit it
docs/        # Specs and plans
```

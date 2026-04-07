# Zero-Touch Intune App Packaging & Deployment Pipeline

Convention-over-configuration **PowerShell 7** pipeline: drop an allowlisted `.msi` or `.exe` into `inbox/`, produce a `.intunewin` with Microsoft’s **Win32 Content Prep Tool**, then publish and assign a Win32 app in **Microsoft Intune** via **Microsoft Graph** (lab / portfolio scope).

## Status

**Scaffold (Task 1)** — Repository layout, secret hygiene, and environment template are in place. Module, scripts, and tests are added in later tasks per the spec.

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
3. Never commit `.env` or real secrets.

## Layout

```text
inbox/       # Drop allowlisted installers here (tracked empty via .gitkeep)
staging/     # Created at runtime; gitignored
done/        # Successfully processed files; gitignored
failed/      # Rejected files; gitignored
tools/       # Readme only — place IntuneWinAppUtil locally, do not commit it
docs/        # Specs and plans
```

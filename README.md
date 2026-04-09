# Zero-Touch Intune App Packaging & Deployment Pipeline

**Drop-folder automation** for **Microsoft Intune**: an allowlisted `.msi` or `.exe` lands in `inbox/`, the pipeline builds a **`.intunewin`** with Microsoft’s **Win32 Content Prep Tool**, then **creates, uploads, and assigns** a Win32 LOB app via **Microsoft Graph**. This repo is a **portfolio build**; structure, auth, and failure handling follow patterns I would use in a **production-adjacent** environment (explicit config, tests, no committed secrets).

**Stack:** PowerShell 7 · Microsoft Graph PowerShell (**beta** APIs for Win32 LOB) · Intune Win32 · Pester · PSScriptAnalyzer  

**Security posture:** `.env.example` only in git; **certificate-based app auth preferred** over client secrets; optional `config.local.json` for paths (gitignored).  

**Proof points:** Pester tests with **mocked Graph** / blob upload; stable **`ERR_*`** codes on failure; idempotent inbox sweep and debounced **FileSystemWatcher** for large installers.

## Quick start

Prerequisites: **PowerShell 7+**, **Microsoft.Graph** modules, **IntuneWinAppUtil.exe**, and an **Entra app registration** with **DeviceManagementApps.ReadWrite.All** (application, admin consent). Copy **`.env.example`** → **`.env`**, fill in values, then **load variables into this PowerShell session** (files on disk are not read automatically):

```powershell
Set-Location <path-to-repo-root>
pwsh -File .\tools\Import-IntuneDropEnv.ps1
```

Then run a drop-folder sweep (from the same session):

```powershell
# One pass: every .exe/.msi in the configured inbox (repeat when the inbox is empty → no work)
pwsh -File .\src\Process-Inbox.ps1 -Once

# Inbox watcher with debounce (Ctrl+C to stop); optional -NoInitialSweep
pwsh -File .\src\Watch-Inbox.ps1 -DebounceSeconds 3
```

See [docs/SPEC.md](docs/SPEC.md) for step-by-step flow and edge cases.

## Project status

Orchestration (**parse → allowlist → pack → Graph → file moves**), Graph publish/assign, and **Process-Inbox** / **Watch-Inbox** entrypoints are in place; portfolio documentation and lab checklists continue under **Task 11**. Detailed task-by-task notes live in **[docs/STATUS.md](docs/STATUS.md)**.

## Documentation

| Document | Purpose |
|----------|---------|
| [docs/SPEC.md](docs/SPEC.md) | Requirements, commands, boundaries, success criteria |
| [docs/IMPLEMENTATION-PLAN.md](docs/IMPLEMENTATION-PLAN.md) | Dependency order, tasks, checkpoints |
| [docs/STATUS.md](docs/STATUS.md) | Task-level implementation status |
| [docs/ideas/drop-folder-intune-convention.md](docs/ideas/drop-folder-intune-convention.md) | Original concept one-pager |

## Configuration

1. Copy `.env.example` to `.env`.
2. Set `INTUNE_DROP_PREP_TOOL_EXE` and Entra/Graph variables. See [tools/README.md](tools/README.md) for where to place the packaging tool.
3. **Graph application credential (pick exactly one in `.env`):**  
   **Preferred:** `AZURE_CLIENT_CERTIFICATE_THUMBPRINT` after you upload a cert to the app registration and import the matching PFX into `Cert:\CurrentUser\My` or `Cert:\LocalMachine\My` (pipeline searches both).  
   **Or:** `AZURE_CLIENT_CERTIFICATE_PATH` to a PFX file kept outside the repo, with optional `AZURE_CLIENT_CERTIFICATE_PASSWORD`.  
   **Legacy/lab:** `AZURE_CLIENT_SECRET` only if you are not using certificate auth.  
   In Entra: **App registrations → your app → Certificates & secrets → Certificates** — upload a public key (create a suitable code-signing or SSL-style cert for app auth per your org; for a lab you can generate a self-signed PFX, upload the **.cer** public part, and import the PFX on the packaging host). Grant **Application** permission **DeviceManagementApps.ReadWrite.All** and **admin consent**, same as before.
4. Optionally add **`config.local.json`** at the repo root (listed in `.gitignore` — do not commit) to override **path** keys only: `INTUNE_DROP_INBOX_PATH`, `INTUNE_DROP_DONE_PATH`, `INTUNE_DROP_FAILED_PATH`, `INTUNE_DROP_STAGING_PATH`. Process environment variables override those JSON values when both are set.
5. Never commit `.env`, PFX files, or real secrets.

After **`Import-IntuneDropEnv.ps1`** (or your own `Set-Item Env:...` commands), verify configuration:

```powershell
Import-Module .\src\Modules\IntuneDropPipeline\IntuneDropPipeline.psd1 -Force
Get-IntuneDropConfiguration
```

### End-to-end lab checklist (first successful drop)

1. **Env:** `Import-IntuneDropEnv.ps1` → `Get-IntuneDropConfiguration` succeeds (no “missing variable” error).
2. **Graph:** `Connect-IntuneDropGraphSession -UseConfiguration` → `Get-MgContext` shows your tenant → `Disconnect-MgGraph` when done testing.
3. **Group:** `INTUNE_DROP_TEST_GROUP_ID` is the Entra **security group** **Object ID** that will receive assignments; add **users** or **devices** you intend to target.
4. **Drop:** Place `Vendor_AppName_x.y.z.exe` or `.msi` in **`inbox/`** → `pwsh -File .\src\Process-Inbox.ps1 -Once` → installer moves to **`done/`** (or **`failed/`** with a reason file).
5. **Intune portal:** App appears under **Apps**; **Assignments** shows your group. **Device install status** / **Monitor** shows per-device results.
6. **Clients:** A PC must be **enrolled in Intune (MDM)**, not only “connected to Entra ID” on the account. **Settings → Access work or school** as an **administrator** to enroll or sync; until the device appears under **Intune → Devices**, Win32 apps from this pipeline will not install there.

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

Packaging example (after configuring `Get-IntuneDropConfiguration`):

```powershell
$c = Get-IntuneDropConfiguration
New-IntuneDropWin32Package -InstallerPath (Join-Path $c.InboxPath 'Contoso_App_1.0.0.msi') -StagingPath $c.StagingPath -PrepToolExe $c.PrepToolExe
```

### Graph publish (lab checklist)

1. `Install-Module Microsoft.Graph -Scope CurrentUser`
2. `Connect-IntuneDropGraphSession -UseConfiguration` (uses certificate or client secret from env per **Configuration** above).
3. Build `$intent` (with MSI **ProductCode** filled for `.msi`), `$pack = New-IntuneDropWin32Package ...`, `$app = New-IntuneDropWin32LobApp -InstallIntent $intent -IntuneWinPath $pack.IntuneWinPath`, `Publish-IntuneDropWin32LobIntuneWinContent -MobileAppId $app.Id -IntuneWinPath $pack.IntuneWinPath`, `New-IntuneDropWin32LobGroupAssignment -MobileAppId $app.Id -GroupId $c.TestGroupId`.
4. `Disconnect-IntuneDropGraphSession` when finished.

Use **`(Get-IntuneDropConfiguration).TestGroupId`** for the Entra group object ID (`INTUNE_DROP_TEST_GROUP_ID`).

## Layout

```text
inbox/       # Drop allowlisted installers here (tracked empty via .gitkeep)
staging/     # Created at runtime; gitignored
done/        # Successfully processed files; gitignored
failed/      # Rejected files; gitignored
tools/       # Import-IntuneDropEnv.ps1 + readme; place IntuneWinAppUtil locally, do not commit it
docs/        # Specs, plans, and status
```

## Development

```powershell
Set-Location <path-to-repo-root>
Invoke-Pester .\tests
```

Static analysis (use the repo **`PSScriptAnalyzerSettings.psd1`** so `Connect-IntuneDropGraphSession`’s env-based client secret → `SecureString` is not flagged as plaintext misuse):

```powershell
Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1 -Severity Error
```

Warnings (BOM, `ShouldProcess`, singular nouns) are accepted for v1 unless you tighten style in a follow-up change.

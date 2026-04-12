<div align="center">

# Zero-Touch Intune App Packaging & Deployment Pipeline

**A lab-hardened, convention-driven automation pipeline that turns allowlisted Win32 installers into published Microsoft Intune Win32 LOB applications—using Microsoft Graph, certificate-first identity, and auditable file outcomes.**

[![Last commit](https://img.shields.io/github/last-commit/DNBLabs/Zero-Touch-Intune-App-Packaging---Deployment-Pipeline)](https://github.com/DNBLabs/Zero-Touch-Intune-App-Packaging---Deployment-Pipeline/commits/main)

</div>

---

## Overview and core principles

This repository demonstrates **endpoint automation and “policy as code”** scaled for a **development or lab tenant**: operators drop versioned `.msi` or `.exe` files into a watched inbox; the system **validates naming and allowlist intent**, produces **`.intunewin`** content with Microsoft’s **Win32 Content Prep Tool**, then drives the **Win32 LOB content lifecycle** through **Microsoft Graph** (including **Azure Blob Storage** upload via SAS as part of Intune’s commit flow), and finally **assigns** a configured Entra ID security group. The design matches how disciplined platform teams treat small, high-risk surfaces—explicit stages, typed failures, and reviewable configuration:

| Principle | How it appears in this repository |
|-----------|-------------------------------------|
| **Automation and modularity** | Thin entry scripts (`Process-Inbox.ps1`, `Watch-Inbox.ps1`) delegate to the **`IntuneDropPipeline`** module with explicit stages (parse → allowlist → pack → Graph → file moves). |
| **Fail closed** | Validation and packaging occur **before** Graph mutations; unsupported drops are rejected and moved to **`failed/`** with traceable logging and stable **`ERR_*`** identifiers where applicable. |
| **Security by default** | Secrets are **never** committed; **`.env.example`** documents variable names only; **certificate-based application authentication** is preferred over long-lived client secrets; optional **`config.local.json`** overrides paths and is gitignored. |
| **Versioned policy** | Install, detection, and uninstall intent for supported packages live in **`IntuneDropAllowlist.json`**, reviewed like any other controlled configuration artifact. |
| **Observable outcomes** | Successful installers move to **`done/`**; failures to **`failed/`**; structured logging via **`Write-IntuneDropLog`**. |
| **Quality gates** | **Pester** tests (including mocked Graph and upload boundaries) and **PSScriptAnalyzer** with repository-specific settings support repeatable review. |

The automation model is a **single trusted packaging host** (physical or virtual) running **PowerShell 7** with access to Entra and Intune. **Inbox sweeps** are idempotent, and **`Watch-Inbox.ps1`** uses a **debounced `FileSystemWatcher`** so large copies settle before processing—suitable for interactive use or **Task Scheduler**-style batch runs.

---

## Repository structure

```text
.
├── .env.example                 # Documented environment variable contract (no secrets)
├── .gitignore                   # Excludes secrets, staging, outcomes, local tooling noise
├── PSScriptAnalyzerSettings.psd1
├── README.md
├── docs/
│   ├── SPEC.md                  # Authoritative requirements and command reference
│   ├── IMPLEMENTATION-PLAN.md   # Dependency-ordered delivery and checkpoints
│   ├── STATUS.md                # Task-level implementation status
│   └── ideas/
│       └── drop-folder-intune-convention.md
├── inbox/                       # Drop folder (tracked empty via .gitkeep)
├── src/
│   ├── Import-IntuneDropRepoDotEnv.ps1   # Loads .env from repo root when invoked by entrypoints
│   ├── Process-Inbox.ps1        # Single-pass inbox processing (-Once required)
│   ├── Watch-Inbox.ps1          # Debounced FileSystemWatcher-driven sweeps
│   └── Modules/
│       └── IntuneDropPipeline/  # Manifest, root module, Public/Private functions, Data/
├── tests/                       # Pester test suite (*.Tests.ps1)
└── tools/
    ├── Import-IntuneDropEnv.ps1 # Helper to load .env into the current session
    └── README.md                # IntuneWinAppUtil placement and env loading notes
```

Runtime directories **`staging/`**, **`done/`**, and **`failed/`** are created as needed and are excluded from version control when they contain artifacts.

---

## Reviewer quick start

This section is for **hiring managers and senior engineers** who want to validate structure, style, and tests **without** standing up a real Intune tenant on the first pass.

### 1. Clone and enter the repository

```powershell
git clone https://github.com/DNBLabs/Zero-Touch-Intune-App-Packaging---Deployment-Pipeline.git
Set-Location .\Zero-Touch-Intune-App-Packaging---Deployment-Pipeline
```

### 2. Static analysis (PSScriptAnalyzer)

Requires the **PSScriptAnalyzer** module (`Install-Module PSScriptAnalyzer -Scope CurrentUser` if needed).

```powershell
Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1 -Severity Error
```

The settings file documents intentional exclusions (for example, building a **SecureString** from an environment-provided secret for **Microsoft Graph** client credentials in lab scenarios).

### 3. Unit tests (Pester 5)

Requires **Pester** 5.x (`Install-Module Pester -Scope CurrentUser` if needed).

```powershell
Invoke-Pester .\tests
```

Tests exercise configuration resolution, parsing, allowlist behavior, packaging boundaries, and Graph-related flows with **mocks**, so a full `.env` file is **not** required for most of the suite. Integration with a live tenant remains a **documented manual checklist** (see `docs/SPEC.md` and the configuration section below).

### 4. Optional: load environment and inspect resolved configuration

After copying **`.env.example`** to **`.env`** and filling placeholders (or exporting variables in your session):

```powershell
pwsh -File .\tools\Import-IntuneDropEnv.ps1
Import-Module .\src\Modules\IntuneDropPipeline\IntuneDropPipeline.psd1 -Force
Get-IntuneDropConfiguration
```

Local verification is intentionally lightweight: **PowerShell 7**, the **Microsoft.Graph** modules, and the **Win32 Content Prep Tool** on a Windows packaging workstation—no auxiliary services are required to run the test suite.

---

## Hardware matrix (packaging host)

The pipeline runs where **PowerShell 7** and **IntuneWinAppUtil** execute; MSI metadata extraction uses **Windows Installer COM** on **Windows** for `.msi` drops.

| Role | Device / VM | CPU | RAM | OS | Notes |
|------|-------------|-----|-----|-----|--------|
| Packaging / operator host | Home Desktop | AMD Ryzen 5 5600X | 32GB | Windows 11 | Install **PowerShell 7**, **Microsoft.Graph** modules, and **IntuneWinAppUtil.exe** per `tools/README.md`. |
| Network | N/A | — | — | — | Requires HTTPS egress to **Microsoft Graph** and Intune-related endpoints
---

## Tech stack and services

Expand each section for components **present in this repository or explicitly required by its documentation**.

<details>
<summary><strong>Runtime, languages, and quality</strong></summary>

- **PowerShell 7** (`pwsh`) — sole supported shell for entrypoints and module code.
- **Pester 5** — automated tests under `tests/`.
- **PSScriptAnalyzer** — static analysis with `PSScriptAnalyzerSettings.psd1`.

</details>

<details>
<summary><strong>Microsoft 365 and Azure (application lifecycle)</strong></summary>

- **Microsoft Intune** — Win32 LOB app creation, content commit, and group assignment (consumer of published packages).
- **Microsoft Graph** — **DeviceManagementApps.ReadWrite.All** (application permission, admin consent) via **Microsoft.Graph** PowerShell modules; **beta** APIs used where required for Win32 LOB flows per module implementation.
- **Entra ID (Azure AD)** — App registration, tenant ID, client ID, **certificate or client secret** credential model.
- **Azure Blob Storage (SAS)** — Used **indirectly** as part of Microsoft’s Win32 content upload protocol (create content version → upload → commit); implemented in module upload completion logic, not as a standalone user-managed storage account in this repo.

</details>

<details>
<summary><strong>Packaging and local tools</strong></summary>

- **Microsoft Win32 Content Prep Tool** (`IntuneWinAppUtil.exe`) — vendor binary, **not** committed; path supplied via **`INTUNE_DROP_PREP_TOOL_EXE`** (see `tools/README.md`).
- **Repository module** — `src/Modules/IntuneDropPipeline/` (manifest `IntuneDropPipeline.psd1`, root `IntuneDropPipeline.psm1`, `Public/`, `Private/`, `Data/IntuneDropAllowlist.json`).

</details>

<details>
<summary><strong>Connectivity, observability, and CI/CD</strong></summary>

- **Connectivity:** The packaging host needs **HTTPS egress** to **Microsoft Graph** and related Intune endpoints (exact URL set per Microsoft documentation and your tenant’s policies).
- **Observability:** **Structured logging** (`Write-IntuneDropLog`), outcome folders (**`done/`** / **`failed/`**), and **Intune admin center** reporting for assigned clients provide an audit trail without a separate metrics stack.
- **CI/CD (optional):** Nothing runs automatically on GitHub unless you add that yourself later. Today, quality checks are the local commands in **Reviewer quick start** (`Invoke-Pester`, `Invoke-ScriptAnalyzer`).

</details>

---

## Automation and deployment

**Trigger model**

1. **Scheduled or ad hoc batch:** `pwsh -File .\src\Process-Inbox.ps1 -Once` runs **`Invoke-IntuneDropInboxSweep`** once over all `.exe` / `.msi` files in the inbox.
2. **Interactive drop folder:** `pwsh -File .\src\Watch-Inbox.ps1` registers **`FileSystemWatcher`** events with a configurable **debounce** so large copies finish before processing; optional **`-NoInitialSweep`** limits runs to new activity.

**Configuration and secrets**

- Entry scripts invoke **`Import-IntuneDropRepoDotEnv.ps1`** so a repo-root **`.env`** can populate process environment variables before module import.
- **`Get-IntuneDropConfiguration`** resolves paths (with safeguards for characters unsupported by the prep tool), tenant and application identifiers, credential mode, test group ID, and prep tool location. Missing required keys produce errors that list **names**, not secret values.
- **Optional** `config.local.json` at the repository root may override **path** keys only; it is gitignored.

**End-to-end flow (single file)**

Orchestration in **`Invoke-IntuneDropForFile`** (summarized): load configuration → parse filename → resolve **MSI ProductCode** when applicable → resolve **allowlist install intent** → build **`.intunewin`** → **`Connect-IntuneDropGraphSession`** unless disabled → create Win32 LOB app → **`Publish-IntuneDropWin32LobIntuneWinContent`** (blob put and commit) → **`New-IntuneDropWin32LobGroupAssignment`** unless skipped → move installer to **`done/`**; on failure, log and move to **`failed/`** with a reason sidecar when possible.

**Updates**

- **Policy and code** ship together via **Git**; extending supported vendors or detection logic means updating **`IntuneDropAllowlist.json`** and/or module code with accompanying **Pester** coverage.
- **Tenant state** (apps and assignments) is driven by Graph calls; this repository does **not** implement automatic supersedence or cleanup of older Intune apps (see `docs/SPEC.md` boundaries).

---

## Disaster recovery and bare-metal bootstrap

Logical rebuild sequence for the **automation host** and **tenant configuration**, derived only from artifacts and docs in this repository:

1. **Install base OS** on the packaging machine (Windows, with PowerShell 7 and network egress to Microsoft 365 / Graph).
2. **Install PowerShell modules:** `Microsoft.Graph` (scope and pinning policy per your organization; see `docs/SPEC.md` for testing commands).
3. **Install Win32 Content Prep Tool** to a known path; set **`INTUNE_DROP_PREP_TOOL_EXE`** in `.env` (see `tools/README.md`).
4. **Clone this repository** to a clean directory; restore **`inbox/.gitkeep`** layout if needed.
5. **Recreate Entra app registration** (or restore from your identity vault): application permissions including **DeviceManagementApps.ReadWrite.All**, admin consent, and **certificate upload** (preferred) or rotated client secret.
6. **Import the client authentication credential** on the host (certificate thumbprint in user or machine store, or secured PFX path outside the repo).
7. **Copy `.env.example` to `.env`** and populate tenant ID, client ID, test security group object ID, and credential fields; never commit the file.
8. **Optional:** create **`config.local.json`** for non-default inbox or outcome paths on this machine.
9. **Verify:** `pwsh -File .\tools\Import-IntuneDropEnv.ps1` then `Get-IntuneDropConfiguration`; run **`Invoke-Pester .\tests`** and **`Invoke-ScriptAnalyzer`** as gates.
10. **Smoke test against a lab tenant:** `Connect-IntuneDropGraphSession -UseConfiguration`, process a known-good allowlisted drop, confirm app and assignment in Intune admin center, then **`Disconnect-IntuneDropGraphSession`**.
11. **Schedule or document** how operators run **`Process-Inbox.ps1 -Once`** (for example Task Scheduler) or **`Watch-Inbox.ps1`** for interactive labs.

Intune **device enrollment**, **group membership**, and **client-side install success** remain outside this repository’s automation surface; they are prerequisites documented in the spec and historical README sections for end-to-end validation.

---

## Additional documentation

| Document | Purpose |
|----------|---------|
| [docs/SPEC.md](docs/SPEC.md) | Requirements, commands, boundaries, success criteria |
| [docs/IMPLEMENTATION-PLAN.md](docs/IMPLEMENTATION-PLAN.md) | Dependency order, tasks, checkpoints |
| [docs/STATUS.md](docs/STATUS.md) | Task-level implementation status |
| [docs/ideas/drop-folder-intune-convention.md](docs/ideas/drop-folder-intune-convention.md) | Original concept one-pager |

---

## Filename convention and allowlist (summary)

Installers in the inbox must follow the strict pattern documented in **`docs/SPEC.md`**: `Vendor_AppName_x.y.z.msi` or `Vendor_AppName_x.y.z.exe` (underscore and version rules apply). Allowlisted behavior is defined in **`src/Modules/IntuneDropPipeline/Data/IntuneDropAllowlist.json`**; extend only with **known** silent switches and detection paths—**fail closed** for unknown vendors.

---

## License and disclaimer

[Insert license if applicable.] This project is intended as a **portfolio and lab** artifact. **Review your organization’s security and change-management policies** before running Graph-write automation in production; use a **dedicated app registration** and **least-privilege** assignments in Entra and Intune.

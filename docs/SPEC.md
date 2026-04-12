# Spec: Zero-Touch Intune Win32 Drop-Folder Pipeline

## ASSUMPTIONS I'M MAKING

Correct these before implementation if any are wrong.

1. **Operator** is endpoint / desktop engineering in a **lab or dev tenant**, not production multi-tenant at scale.
2. **PowerShell 7+** (`pwsh`) is the only required shell; Windows PowerShell 5.1 is not a target.
3. **Microsoft Win32 Content Prep Tool** (`IntuneWinAppUtil.exe`) is present locally; path is supplied via config/env (not vendored in repo).
4. **Authentication** uses an **Azure AD app registration** with client secret or certificate, called from the script using the **official Microsoft Graph PowerShell SDK** (`Microsoft.Graph` modules) — not raw tokens checked into git.
5. **MVP behavior** is **convention-over-configuration** per `docs/ideas/drop-folder-intune-convention.md`: strict filename pattern, allowlisted install/detection logic, **fail closed** (no assignment) when validation fails.
6. **Intune app lifecycle for v1**: each successful drop creates a **new** Win32 app in Intune whose **display name** includes vendor, app name, and version from the filename (multiple versions = multiple apps; **no automatic supersedence** in v1).
7. **Trigger model for v1**: processing runs when the operator invokes a **watcher script** that uses `FileSystemWatcher` (with debounce) so the demo story stays “drop file → pipeline runs”; a **non-watching** “process inbox once” mode exists for tests and Task Scheduler.
8. **Demo installers** are **chosen and fixed in README** (one `.msi` and one `.exe` family maximum for v1); the allowlist in code matches that table only.
9. **Secrets** live only in environment variables and/or a **gitignored** `config.local.json`; repository contains **`.env.example`** listing variable names with dummy values.

## Objective

Build a **portfolio-grade, minimal** pipeline: an operator drops a **`.exe` or `.msi`** into a single **inbox** folder. A PowerShell flow validates the **filename convention**, picks a **known silent-install and detection pattern**, runs **IntuneWinAppUtil** to produce `.intunewin`, uses **Microsoft Graph** to upload Win32 app content, and **assigns** the app to **one preconfigured Entra ID group** (test ring). Unsupported files **must not** be assigned; they **must** be logged and moved to **`failed/`**. Successful runs move sources/archives to **`done/`** (or equivalent) for a clear audit trail.

**Success for the operator** = fewer manual Intune clicks and **no silent failure** (wrong detection / guessed switches).

**Success for the portfolio** = README-driven setup, **secure secret handling**, structured logging, and **documented boundaries** (what is allowlisted vs rejected).

### User stories (MVP)

- As an **endpoint engineer**, I drop `Contoso_DemoApp_1.0.0.msi` into `inbox/` and, after the pipeline runs, I see a **new Win32 app** in Intune assigned to my **test group**.
- As an **endpoint engineer**, I drop a file that **violates naming or allowlist rules** and the file ends in **`failed/`** with a **log line that states the exact rule violated**.
- As a **reviewer of the portfolio**, I can configure the pipeline using **`.env.example` → real env** and run documented commands without hunting for magic strings in code.

## Tech Stack

| Layer | Choice |
|--------|--------|
| Runtime | PowerShell 7+ |
| Packaging | Microsoft Win32 Content Prep Tool (Microsoft-hosted) |
| API | Microsoft Graph (Device Management / Win32 LOB) |
| Auth | Azure AD app registration + Microsoft Graph PowerShell SDK |
| Validation | Filename parsing + allowlist table (in module or config) |

**Pinned intent (versions to confirm at implement time):** specify minimum `Microsoft.Graph` module version in `README.md` once verified in lab tenant.

## Commands

All commands assume repo root as current directory.

```powershell
# Install Graph modules (once per machine / CI image)
Install-Module Microsoft.Graph -Scope CurrentUser -Force

# Static analysis (requires PSScriptAnalyzer module)
Invoke-ScriptAnalyzer -Path .\src -Recurse -Severity @('Error','Warning')

# Run unit tests (Pester v5)
Invoke-Pester .\tests -Output Detailed

# Process inbox once (no file watcher); useful for tests and scheduled tasks
pwsh -File .\src\Process-Inbox.ps1 -Once

# Run watcher (default demo: monitors inbox continuously)
pwsh -File .\src\Watch-Inbox.ps1

# End-to-end dry checklist (manual; document in README — no fake tenant in repo)
# pwsh -File .\src\Process-Inbox.ps1 -Once -WhatIf   # if implemented; otherwise document manual Graph verification steps
```

**Note:** If `Invoke-ScriptAnalyzer` or `Invoke-Pester` are not installed, `npm`-style scripts are not used; README documents **`Install-Module`** prerequisites explicitly.

## Project Structure

```text
repo-root/
├── .env.example              → Names of env vars; no real secrets
├── .gitignore                → Includes .env, config.local.json, output/temp paths
├── README.md                 → Setup, tenant prep, convention table, demo script
├── docs/
│   ├── SPEC.md               → This document (living spec)
│   └── ideas/
│       └── drop-folder-intune-convention.md
├── inbox/                    → Operator drop folder (empty in git; may use .gitkeep)
├── done/                     → Successfully processed originals + metadata (gitignored contents optional)
├── failed/                   → Rejected drops + reason (gitignored contents optional)
├── staging/                  → Per-job scratch (intunewin build); gitignored
├── tools/                    → README only: where to place IntuneWinAppUtil locally (not committed)
├── src/
│   ├── Watch-Inbox.ps1       → Entry: FileSystemWatcher + debounce → invoke processor
│   ├── Process-Inbox.ps1     → Entry: single pass over inbox
│   └── Modules/
│       └── IntuneDropPipeline/   → Logic: parse name, validate, pack, graph, move files
└── tests/
    └── *.Tests.ps1           → Pester tests (naming, allowlist, path handling; Graph mocked)
```

Paths like `inbox/`, `done/`, `failed/` may be **overridden** via env (e.g. `INTUNE_DROP_INBOX_PATH`).

## Code Style

- **Module manifest** under `src/Modules/IntuneDropPipeline/` with **root module** `.psm1`.
- Every **`.ps1`** and **`.psm1`**: file-level comment describing the module/script purpose; every **function** has **comment-based help** (`SYNOPSIS`, `PARAMETER`, `OUTPUTS`) or an equivalent short doc block — enough that a junior admin can follow without reading the spec.
- **`Verb-Noun`** naming for exported functions; private helpers prefixed or kept in `private/` dot-sourced files if the module grows.
- **No secrets** in code; configuration is read from **environment** and validated at startup with **explicit errors** listing **missing variable names** (not values).

**Example (illustrative only):**

```powershell
function Get-DropPackageFromFileName {
    <#
    .SYNOPSIS
        Parses a strictly formatted installer filename into vendor, app, version, and extension.
    .OUTPUTS
        [pscustomobject] or throws with a rule id suitable for logging.
    #>
    param(
        [Parameter(Mandatory)]
        [string] $FileName
    )
    # Implementation: regex + validation; throw typed errors — do not return $null silently.
}
```

## Testing Strategy

| Level | Tool | Scope |
|--------|------|--------|
| Unit | Pester 5.x | Filename parsing, allowlist resolution, path moves, “fail closed” branches |
| Static | PSScriptAnalyzer | `src/` and `tests/` — Error/Warning severity gates CI locally |
| Integration | Manual / lab | Real Graph upload against dev tenant (documented checklist in README; not automated in CI without secrets) |

**Coverage expectation:** core parsing and validation **≥ 80%** of statements in `IntuneDropPipeline` module where mockable; Graph calls **wrapped** behind functions that tests mock.

**Do not** record live access tokens or tenant IDs in test fixtures.

## Boundaries

### Always

- Validate filename and allowlist **before** invoking IntuneWinAppUtil or Graph.
- Log **rule id + file path + safe metadata**; on Graph failure, log **response detail to file** (not echo secrets).
- Keep **`.env.example`** in sync when new configuration keys are added.
- Run **Pester** and **PSScriptAnalyzer** before treating a task as done (when modules exist).

### Ask first

- Adding **new NuGet/external** dependencies beyond **Microsoft.Graph** modules.
- Changing **assignment model** (e.g. more than one group, filters, intent).
- Implementing **automatic supersedence** or deleting existing Intune apps.

### Never

- Commit **client secrets**, certificates, `.env`, or **`config.local.json`** with real values.
- **Guess** silent switches for EXEs outside the documented allowlist.
- **Assign** an app to the test group when **validation or packaging** failed.

## Success Criteria (testable)

1. **Convention pass:** With valid env and tools, dropping an allowlisted installer matching `Vendor_AppName_x.y.z.msi` **or** `Vendor_AppName_x.y.z.exe` (per allowlist) results in a **new Win32 app** in Intune (visible in portal) **assigned** to the configured group within **15 minutes** (or documented sync window), and the installer **appears under `done/`** (or configured archive path). **Lab:** Operator-validated 2026-04-09 with **7-Zip** (`.exe` path) through to install on an enrolled device.
2. **Convention fail:** A file named `setup.exe` (no convention) ends in **`failed/`** and the log contains a **specific validation failure** (e.g. `ERR_FILENAME_CONVENTION`).
3. **Security:** `grep`/search in repo for **GUID patterns of secrets** or literal `client_secret` assignments returns **no committed values**; only env placeholders.
4. **README:** A new engineer can follow **setup from zero** through **first successful assignment** using only README + `.env.example` (within assumption of existing Entra app + group).
5. **Tests:** `Invoke-Pester .\tests` passes locally with **no network** (Graph mocked or files-only tests).

## Open Questions

1. **Exact filename regex** — **Resolved for v1:** `Vendor_AppName_x.y.z.msi|exe` (no underscores inside vendor/app segments; version 2–4 numeric segments). See README and `Get-IntuneDropPackageFromFileName`.
2. **Detection rule strategy for MSI** — **Resolved:** **ProductCode** via Windows Installer COM on Windows (`Get-IntuneDropMsiProductCode`); non-Windows / COM failure → `ERR_MSI_METADATA`.
3. **Which two demo apps** lock the allowlist for v1 (names redistributable in public README)? — **Open:** portfolio uses generic allowlist rows; operators supply their own installers under the naming convention.
4. **Graph API surface** — **Resolved for this repo:** **beta** `deviceAppManagement` paths for Win32 LOB create, content upload, and assignments; confirm against [Microsoft Graph beta Intune](https://learn.microsoft.com/graph/api/resources/intune-graph-overview) if your tenant or national cloud differs.

---

## Implementation plan (Phase 2 — approved spec)

### Major components and dependencies

```text
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│ Watch-Inbox.ps1 │────►│ IntuneDropPipeline   │────►│ IntuneWinAppUtil │
│ Process-Inbox   │     │ (parse / validate /  │     │ (.intunewin)     │
└─────────────────┘     │  pack / graph / fs)  │     └────────┬────────┘
                        └──────────┬───────────┘              │
                                   │                           │
                                   ▼                           ▼
                        ┌──────────────────────┐     ┌─────────────────┐
                        │ Config / logging     │     │ Microsoft Graph │
                        │ (env, paths, errors) │     │ (Win32 LOB)     │
                        └──────────────────────┘     └─────────────────┘
```

| Component | Responsibility | Depends on |
|-----------|----------------|------------|
| **Config layer** | Read env (and optional `config.local.json`), validate required keys, resolve `inbox` / `done` / `failed` / `staging` / prep tool path | None |
| **Naming & allowlist** | Parse `Vendor_AppName_x.y.z.{msi\|exe}`; map extension + optional app key to install/uninstall/detection templates | Config (allowlist table location) |
| **Packaging** | Copy installer to isolated staging dir, shell out to `IntuneWinAppUtil.exe` with documented args, verify `.intunewin` output | Config paths |
| **Graph service** | Connect with `Connect-MgGraph` (app-only), create Win32 LOB app, upload content file in chunked session (or SDK pattern), create assignment to single group | Microsoft.Graph modules, Azure app registration |
| **File lifecycle** | Atomic-ish moves: inbox → processing lock → `done` or `failed` with reason file or log correlation | PowerShell filesystem |
| **Watch-Inbox.ps1** | `FileSystemWatcher`, debounce (e.g. 2–5 s after last change), call single-file processor; handle rename/copy-complete events | Processor |
| **Process-Inbox.ps1** | `-Once`: enumerate inbox `*.exe` / `*.msi`, skip hidden/incomplete (optional `.tmp` exclusion), invoke pipeline per file | Module |

**Dependency order:** Config → Naming → (Packaging + Graph interface stubs) → Orchestrator → Watcher → Integration tests / README.

### Implementation order

1. **Repo scaffold** — `.gitignore`, `.env.example`, folder layout, `README` skeleton, `inbox/.gitkeep`.
2. **`IntuneDropPipeline` module shell** — manifest, public/private split, `Get-*` config from env, structured logging helper (timestamp, level, rule id, message).
3. **Filename parser + validation errors** — throw typed errors / records with stable **`ERR_*`** codes; unit tests first (TDD for parsing).
4. **Allowlist table** — embed in module or `config/allowlist.json` committed (no secrets); README table mirrors v1 rows.
5. **MSI detection strategy (decision)** — document in README: e.g. read **ProductCode** via `WindowsInstaller.Installer` COM (Windows-only) *or* use documented static detection for the one demo MSI only for absolute minimal MVP; spec Open Question #2 — I'll plan **pick COM for MSI product code when `.msi`**, with try/catch and clear `ERR_MSI_METADATA` if COM unavailable (e.g. non-Windows) — spec says PS7 Windows typically; note Linux not supported for MSI path.
6. **Staging + IntuneWinAppUtil invocation** — subprocess, capture stdout/stderr to log; failure → `failed/`.
7. **Graph layer** — thin functions: `Connect-IntuneDropGraph`, `New-IntuneDropWin32App`, `Publish-IntuneDropContent`, `New-IntuneDropGroupAssignment`; tests mock with `-ModuleName` or wrapper injection.
8. **Orchestrator** — single entry `Invoke-IntuneDropForFile` that composes steps and **never assigns** if prior step failed.
9. **`Process-Inbox.ps1 -Once`** — wire orchestrator, enumerate files.
10. **`Watch-Inbox.ps1`** — debounced watcher calling same path as single-file processing.
11. **README** — tenant prep, Graph permissions list, convention table, demo script, troubleshooting.
12. **Manual lab checklist** — document Graph permission names and portal verification steps.

### Risks and mitigation

| Risk | Mitigation |
|------|------------|
| **Win32 LOB upload uses beta / multipart complexity** | Implement against official Microsoft sample flow; pin **module version** and document; time-box spike in first Graph task. |
| **FileSystemWatcher double-fires or incomplete copies** | Debounce; optional “stable size” poll before process; document “copy file then rename into inbox” for large files. |
| **MSI product code extraction fails** | Fail closed with `ERR_MSI_METADATA`; README lists requirement (Windows + COM). |
| **App-only Graph permissions missing in tenant** | README lists exact **Application** permissions and admin consent; orchestrator logs Graph error body on failure. |
| **Secret leakage in errors** | Never log client secret; sanitize MgGraph exceptions per boundary rules. |

### Parallel vs sequential

- **Parallel:** Unit tests for parsing vs allowlist JSON schema validation (if any). README tenant section vs `.env.example` (mostly sequential after env names frozen).
- **Sequential:** Parser before orchestrator; packaging before Graph (need `.intunewin` path); module before watcher scripts.

### Verification checkpoints

| Checkpoint | Verify |
|------------|--------|
| **After parser + tests** | `Invoke-Pester` green; invalid names produce correct `ERR_*`. |
| **After prep tool integration** | Manual: known MSI produces `.intunewin` under `staging/` from `-Once` with Graph calls **disabled** or mocked. |
| **After Graph integration** | Lab tenant: one end-to-end drop creates app + assignment; file in `done/`. |
| **Before “portfolio complete”** | PSScriptAnalyzer clean; README followed by second person (self dry-run). |

---

## Task list (Phase 3)

Each task ≤ ~5 files; order by dependency.

- [ ] **Task: Repo scaffold and secrets hygiene**
  - **Acceptance:** `.gitignore` excludes `.env`, `config.local.json`, `staging/**`, optional `done/**` / `failed/**`; `.env.example` lists all required variables with dummy values; `inbox/.gitkeep` exists; `tools/README.md` explains Content Prep placement.
  - **Verify:** `git status` shows no secrets; folders exist from clean clone + README instructions.
  - **Files:** `.gitignore`, `.env.example`, `inbox/.gitkeep`, `tools/README.md`, `README.md` (skeleton).

- [ ] **Task: `IntuneDropPipeline` module scaffold + configuration**
  - **Acceptance:** Manifest loads; `Get-IntuneDropConfiguration` (name per your verb list) returns resolved paths from env; missing required env throws listing **names** of missing keys only.
  - **Verify:** `Import-Module` succeeds; Pester tests for config happy/missing path.
  - **Files:** `src/Modules/IntuneDropPipeline/IntuneDropPipeline.psd1`, `.psm1`, `private/Get-Configuration.ps1` (or equivalent), `tests/Configuration.Tests.ps1`.

- [ ] **Task: Filename convention parser**
  - **Acceptance:** Valid `Vendor_AppName_1.2.3.msi` parses; invalid names throw or return failure with stable `ERR_FILENAME_CONVENTION` (or similar) documented in README.
  - **Verify:** `Invoke-Pester` on parser tests only; no network.
  - **Files:** `src/Modules/IntuneDropPipeline/Public/`, `tests/Parser.Tests.ps1`.

- [ ] **Task: Allowlist + install/detection builder**
  - **Acceptance:** For each v1 demo row in README, builder returns deterministic install command, uninstall, detection; unknown combo → `ERR_ALLOWLIST`.
  - **Verify:** Pester table-driven tests.
  - **Files:** Module allowlist + `tests/Allowlist.Tests.ps1`.

- [ ] **Task: MSI metadata (product code) helper**
  - **Acceptance:** For sample MSI (or mock), product code readable on Windows; failure surfaces `ERR_MSI_METADATA`.
  - **Verify:** Pester with mock where possible; one manual test with real `.msi` documented.
  - **Files:** `src/Modules/IntuneDropPipeline/Private/Get-MsiProductCode.ps1` (example name), tests.

- [ ] **Task: Invoke IntuneWinAppUtil**
  - **Acceptance:** Given valid installer + staging path, produces `.intunewin`; non-zero exit logs stderr and throws `ERR_PACKAGING`.
  - **Verify:** Manual or CI with prep tool installed; Pester can mock `Start-Process`.
  - **Files:** `src/Modules/IntuneDropPipeline/Private/`, tests with mocks.

- [ ] **Task: Graph wrapper (auth + create app + upload + assign)**
  - **Acceptance:** Functions isolated; Pester mocks `Invoke-MgGraphRequest` or module commands; real tenant works when run manually per README.
  - **Verify:** Mocks: tests pass offline; manual: one app assigned to test group.
  - **Files:** `src/Modules/IntuneDropPipeline/Private/Graph*.ps1` (split if needed), `tests/Graph.Tests.ps1`.

- [ ] **Task: Orchestrator + file moves**
  - **Acceptance:** `Invoke-IntuneDropForFile` runs full chain; success → `done/`; validation/packaging/graph failure → `failed/` and no assignment on partial failure.
  - **Verify:** Pester integration-style with temp dirs; manual E2E optional.
  - **Files:** `src/Modules/IntuneDropPipeline/Public/Invoke-IntuneDropForFile.ps1`, tests.

- [ ] **Task: `Process-Inbox.ps1 -Once`**
  - **Acceptance:** Processes all eligible files in inbox once; idempotent behavior documented (e.g. skip if file gone).
  - **Verify:** Manual drop test + Pester.
  - **Files:** `src/Process-Inbox.ps1`.

- [ ] **Task: `Watch-Inbox.ps1`**
  - **Acceptance:** Debounced watcher invokes same logic as single file; graceful stop (Ctrl+C) documented.
  - **Verify:** Manual: drop file while watcher runs.
  - **Files:** `src/Watch-Inbox.ps1`.

- [ ] **Task: README + manual checklist**
  - **Acceptance:** Graph app permissions, convention table, demo apps named, troubleshooting; matches `.env.example`.
  - **Verify:** Self dry-run from clean env; `Invoke-ScriptAnalyzer` on `src/`.
  - **Files:** `README.md`, `docs/SPEC.md` (update Open Questions when resolved).

---

## Document control

| Phase | Status |
|--------|--------|
| Specify | **Approved** |
| Plan | **Complete** (mirrored in [IMPLEMENTATION-PLAN.md](./IMPLEMENTATION-PLAN.md)) |
| Tasks | **Complete** (checklist above; live status in [STATUS.md](./STATUS.md)) |
| Implement | **Complete (portfolio / lab)** — core pipeline shipped; **Task 11** closed after operator lab 2026-04-09 (7-Zip E2E including device install). See [STATUS.md](./STATUS.md). |

After scope or decisions change, update **Open Questions**, **Commands** (e.g. PSScriptAnalyzer `-Settings`), and this document so it stays the source of truth alongside [README.md](../README.md).

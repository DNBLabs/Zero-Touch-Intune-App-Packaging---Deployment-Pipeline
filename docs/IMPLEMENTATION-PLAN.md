# Implementation Plan: Zero-Touch Intune Win32 Drop-Folder Pipeline

## Overview

Deliver a **convention-over-configuration** PowerShell pipeline: operators drop a allowlisted `.msi` / `.exe` into `inbox/`; the tool validates naming, builds `.intunewin` with Microsoft Win32 Content Prep, publishes a **new** Win32 app via Microsoft Graph, assigns one **test group**, and moves outcomes to **`done/`** or **`failed/`**. Work is sliced so each phase leaves a **verifiable** state (tests or manual checklist). Authoritative requirements live in [`SPEC.md`](./SPEC.md); this document is the **execution-oriented** breakdown (dependencies, sizing, checkpoints).

## Architecture decisions

- **Single module boundary** — `IntuneDropPipeline` owns config, parse, allowlist, pack, graph wrappers, orchestration; scripts are thin entrypoints.
- **Fail closed** — No Graph assignment unless validation and packaging succeeded; failures use stable **`ERR_*`** codes in logs.
- **v1 lifecycle** — Each success creates a **new** Intune app (version in display name); no supersedence automation.
- **MSI detection** — ProductCode via **Windows Installer COM** on Windows; non-Windows / COM failure → `ERR_MSI_METADATA`.
- **Secrets** — Environment variables + optional gitignored `config.local.json`; `.env.example` only in repo.

## Dependency graph

```text
Repo scaffold + .gitignore / .env.example
        │
        ▼
Module shell + configuration + logging
        │
        ├──► Filename parser ──►┐
        │                       ├──► Allowlist / intent builder ──► MSI ProductCode helper
        │                       │
        └──► (paths for staging) ► IntuneWinAppUtil integration
                                        │
                                        ├──► Graph: auth + create Win32 app
                                        │
                                        └──► Graph: upload content + group assignment
                                                │
                                                ▼
                                        Orchestrator + file moves (done/failed)
                                                │
                    ┌──────────────────────────┴──────────────────────────┐
                    ▼                                                      ▼
            Process-Inbox.ps1 -Once                              Watch-Inbox.ps1
                    │
                    └──────────────────────► README + manual lab checklist
```

**Build order:** Top to bottom; **Graph upload** depends on **`.intunewin`**; **orchestrator** depends on **pack** and **Graph** pieces.

## Vertical slices (working behavior at each stage)

| Slice | What works end-to-end | Tasks involved |
|--------|------------------------|----------------|
| **V1 — Hygiene** | Clone repo; no secrets committed; paths documented | Task 1 |
| **V2 — Config loads** | Import module; missing env fails with **names only** | Task 2 |
| **V3 — Smart validation** | Bad filename → predictable `ERR_*` (no side effects) | Task 1–3 |
| **V4 — Intention locked** | Valid name + allowlist → deterministic install/uninstall/detection; MSI has product code when applicable | Task 4–5 |
| **V5 — Pack only** | Valid drop produces `.intunewin` under staging (Graph can be stubbed/off) | Task 6 |
| **V6 — Tenant publish** | Full chain: pack + create app + upload + assign in lab | Task 7–8 |
| **V7 — Operator UX** | `-Once` and **watcher** both drive same orchestrator | Task 9–10 |
| **V8 — Portfolio** | README + analyzer + human checklist | Task 11 |

Each slice should stay **working** after its checkpoint (tests green; manual step documented where Graph is required).

## Task list

### Phase 1: Foundation

#### Task 1: Repo scaffold and secrets hygiene

**Description:** Create folder layout, ignore rules, and placeholder env documentation so contributors cannot accidentally commit paths, packages, or secrets.

**Acceptance criteria:**

- [ ] `.gitignore` excludes `.env`, `config.local.json`, `staging/`, and documents optional ignores for `done/`, `failed/`.
- [ ] `.env.example` lists every required variable name with **placeholder** values only.
- [ ] `inbox/` exists with `.gitkeep`; `tools/README.md` explains where to put `IntuneWinAppUtil.exe` locally.
- [ ] Root `README.md` exists as a skeleton pointing to `SPEC.md` and this plan.

**Verification:**

- [ ] Fresh clone: `inbox` and `tools` paths exist; no real secrets in tracked files.
- [ ] Manual: search repo for assignment of literal client secrets — none.

**Dependencies:** None

**Files likely touched:** `.gitignore`, `.env.example`, `inbox/.gitkeep`, `tools/README.md`, `README.md`

**Estimated scope:** Small — mostly new empty paths and boilerplate (multiple small files, little logic)

---

#### Task 2: `IntuneDropPipeline` module scaffold and configuration

**Description:** Add manifest and root module; implement configuration discovery from environment (and optional local config file contract); add a small structured logging helper used by later tasks.

**Acceptance criteria:**

- [ ] `Import-Module ./src/Modules/IntuneDropPipeline` succeeds.
- [ ] Exported function resolves **inbox**, **done**, **failed**, **staging**, and **IntuneWinAppUtil** path from env per `SPEC.md`.
- [ ] Missing required keys throw with **only** missing **key names**, not values.

**Verification:**

- [ ] `Invoke-Pester ./tests -PathFilter *Configuration*` passes.
- [ ] Manual: unset one required var → error lists that name.

**Dependencies:** Task 1

**Files likely touched:** `IntuneDropPipeline.psd1`, `IntuneDropPipeline.psm1`, `Private/Get-IntuneDropConfiguration.ps1` (or equivalent), `Private/Write-IntuneDropLog.ps1`, `tests/Configuration.Tests.ps1`

**Estimated scope:** Medium (3–5 files)

---

### Checkpoint: Foundation

- [ ] `Invoke-Pester` for configuration tests passes.
- [ ] Module imports on a clean machine with only env vars set.
- [ ] Proceed only if folder layout matches `SPEC.md`.

---

### Phase 2: Validation and intent (no Graph)

#### Task 3: Filename convention parser

**Description:** Implement strict parsing for `Vendor_AppName_x.y.z.msi|exe` (exact regex finalized in README + tests); emit stable error codes for all failure modes.

**Acceptance criteria:**

- [ ] Valid examples parse to vendor, app name, version, extension.
- [ ] Invalid examples yield `ERR_FILENAME_CONVENTION` (or documented variant) — no silent `$null`.
- [ ] Behavior covered by Pester without network.

**Verification:**

- [ ] `Invoke-Pester ./tests -PathFilter *Parser*` passes.

**Dependencies:** Task 2

**Files likely touched:** `Public/Get-IntuneDropPackageFromFileName.ps1` (example), `tests/Parser.Tests.ps1`

**Estimated scope:** Small–medium

---

#### Task 4: Allowlist and install/detection builder

**Description:** Map parsed package + extension to **known** silent switches and detection templates matching the README convention table (one MSI row + one EXE row for v1).

**Acceptance criteria:**

- [ ] Table-driven tests cover each committed allowlist row.
- [ ] Unknown combination returns `ERR_ALLOWLIST`.

**Verification:**

- [ ] `Invoke-Pester ./tests -PathFilter *Allowlist*` passes.

**Dependencies:** Task 3

**Files likely touched:** `Private/Get-IntuneDropInstallIntent.ps1` (example), `config/allowlist.json` **or** data section in module, `tests/Allowlist.Tests.ps1`

**Estimated scope:** Medium

---

#### Task 5: MSI ProductCode helper

**Description:** Read MSI **ProductCode** via Windows Installer COM for detection rules; non-Windows or COM failure → `ERR_MSI_METADATA`.

**Acceptance criteria:**

- [ ] Windows + valid `.msi`: returns consistent product code string.
- [ ] Failure paths logged with rule id; no partial Graph side effects (not yet invoked).

**Verification:**

- [ ] Pester uses mocks where possible.
- [ ] Manual: one real `.msi` in lab documented in README.

**Dependencies:** Task 4

**Files likely touched:** `Private/Get-IntuneDropMsiProductCode.ps1`, `tests/MsiMetadata.Tests.ps1`

**Estimated scope:** Small–medium

---

### Checkpoint: Validation stack

- [ ] Invalid names and allowlist misses never call packaging or Graph (unit test with mock orchestrator or future hook).
- [ ] All Phase 2 tests green offline.

---

### Phase 3: Packaging

#### Task 6: Invoke IntuneWinAppUtil

**Description:** Copy installer into isolated staging, invoke prep tool with documented arguments, capture output, validate `.intunewin` exists; failures throw `ERR_PACKAGING` and log stderr.

**Acceptance criteria:**

- [ ] Success path produces exactly one expected `.intunewin` path.
- [ ] Non-zero exit from prep tool → no Graph calls in later orchestrator wiring.

**Verification:**

- [ ] Pester mocks `Start-Process` (or wrapper) for CI.
- [ ] Manual: real tool run produces package under `staging/`.

**Dependencies:** Tasks 2, 5 (for a full intent path; 2 alone for “dry” path tests)

**Files likely touched:** `Private/New-IntuneDropWin32Package.ps1`, `tests/Packaging.Tests.ps1`

**Estimated scope:** Medium

---

### Checkpoint: Pack-only

- [ ] Orchestrator stub or manual script: valid file → `.intunewin` on disk.
- [ ] README lists exact Content Prep version / args used.

---

### Phase 4: Microsoft Graph

#### Task 7: Graph wrapper — auth, Win32 app, upload, assign

**Description:** Thin functions: app-only auth, create Win32 LOB app, upload content (SDK or REST per spike), assign to single Entra group ID from config. All Graph errors log response body to log file; no secret leakage.

**Acceptance criteria:**

- [ ] Functions are individually mockable; Pester passes **offline** with mocked `Invoke-MgGraphRequest` / cmdlets.
- [ ] Manual lab: one drop results in visible app + assignment.

**Verification:**

- [ ] `Invoke-Pester ./tests -PathFilter *Graph*` passes without network.
- [ ] Manual checklist in README completed once.

**Dependencies:** Task 2 (config); Task 6 conceptually before **assignment** in orchestrator, but Graph functions can be built with mock file paths.

**Files likely touched:** `Private/Connect-IntuneDropGraph.ps1`, `Private/New-IntuneDropWin32App.ps1`, `Private/Publish-IntuneDropWin32Content.ps1`, `Private/New-IntuneDropGroupAssignment.ps1`, `tests/Graph.Tests.ps1`

**Estimated scope:** Large — **cap at five files** by combining small wrappers or splitting into Task 7a/7b only if this becomes a bottleneck:

| Optional split | Focus |
|----------------|--------|
| **Task 7a** | Auth + create app record only |
| **Task 7b** | Content upload + assignment |

---

### Phase 5: Orchestration and entrypoints

#### Task 8: Orchestrator and file moves

**Description:** `Invoke-IntuneDropForFile` composes parse → allowlist → MSI metadata → pack → graph → moves; **never** assign if earlier step failed; move source to `done/` or `failed/`.

**Acceptance criteria:**

- [ ] Atomic-ish behavior documented (best-effort lock / move ordering).
- [ ] Integration-style Pester tests with temp directories.

**Verification:**

- [ ] Pester passes; manual E2E optional.

**Dependencies:** Tasks 3–7

**Files likely touched:** `Public/Invoke-IntuneDropForFile.ps1`, `tests/Orchestrator.Tests.ps1`

**Estimated scope:** Medium

---

#### Task 9: `Process-Inbox.ps1 -Once`

**Description:** Enumerate `*.exe` / `*.msi` in inbox; invoke orchestrator per file; document idempotency (file moved, skip missing).

**Acceptance criteria:**

- [ ] `-Once` switch processes all current inbox files then exits.
- [ ] Duplicate run does not reprocess moved files.

**Verification:**

- [ ] Manual drop test + Pester where filesystem can be faked.

**Dependencies:** Task 8

**Files likely touched:** `src/Process-Inbox.ps1`, `tests/ProcessInbox.Tests.ps1` (optional)

**Estimated scope:** Small

---

#### Task 10: `Watch-Inbox.ps1`

**Description:** `FileSystemWatcher` with debounce; calls same single-file path as Task 9; Ctrl+C exits cleanly.

**Acceptance criteria:**

- [ ] Drop-in while running triggers processing after debounce window.
- [ ] README notes large-file copy pattern (rename into inbox when complete).

**Verification:**

- [ ] Manual: drop file while watcher runs end-to-end in lab.

**Dependencies:** Task 8

**Files likely touched:** `src/Watch-Inbox.ps1`

**Estimated scope:** Small

---

### Checkpoint: Core product path

- [x] Lab tenant shows new app per successful drop; failures land in `failed/`. *(Validated 2026-04-09: 7-Zip via drop folder → device install.)*
- [ ] Watcher and `-Once` both validated at least once. *(`Process-Inbox.ps1 -Once` / full chain confirmed; confirm `Watch-Inbox.ps1` separately if you need both boxes checked.)*

---

### Phase 6: Portfolio completion

#### Task 11: README and manual lab checklist

**Description:** Finalize operator setup: Entra app registration, **Application** permissions, admin consent, convention table, demo apps, troubleshooting, commands aligned with `SPEC.md`. Run `Invoke-ScriptAnalyzer` on `src/` with **`PSScriptAnalyzerSettings.psd1`** (excludes the env-only `ConvertTo-SecureString -AsPlainText` rule for Graph client secret). Close applicable **Open Questions** in `SPEC.md`.

**Acceptance criteria:**

- [x] README matches `.env.example` keys and folder layout.
- [x] `Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1 -Severity Error` produces **zero** errors (remaining warnings documented in README **Development**).
- [x] Second-person dry-run (you or peer) completes checklist without guesswork. *(Operator lab completed 2026-04-09; 7-Zip uploaded and installed on device.)*

**Verification:**

- [ ] Analyzer output saved or pasted in PR notes (optional).
- [x] `SPEC.md` Open Questions updated for decisions made.

**Dependencies:** Tasks 1–10

**Files likely touched:** `README.md`, `docs/SPEC.md`

**Estimated scope:** Medium (mostly documentation)

---

### Checkpoint: Complete

- [x] All success criteria in `SPEC.md` are met or consciously deferred with a note. *(E2E lab validates convention pass + README path; see [STATUS.md](./STATUS.md).)*
- [x] Ready for portfolio / code review.

---

## Parallelization opportunities

| Parallel track A | Parallel track B | Note |
|------------------|------------------|------|
| Task 1 (scaffold) | — | Start alone |
| Task 3 (parser tests) | Task 1 follow-up docs | After Task 2, parser tests need module config |
| README troubleshooting draft | Task 7 (Graph) spike | Only after env names stable; avoid permission drift |

**Do not parallelize:** Orchestrator (Task 8) before Graph (Task 7) contract exists; **Watch-Inbox** before orchestrator stable.

## Risks and mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Graph Win32 upload complexity / beta APIs | High | Time-box spike in Task 7; pin module version; document tenant SKU |
| FileSystemWatcher races | Medium | Debounce + README copy/rename guidance |
| MSI COM unavailable | Medium | `ERR_MSI_METADATA`; README states Windows-only for MSI |
| Scope creep (supersedence, UI) | Medium | Defer per `SPEC.md` **Not Doing** |

## Open questions (carry from `SPEC.md`)

- Final **filename regex** (hyphens, four-part versions).
- **Exact** v1 demo installers named in README (publicly redistributable).
- **Stable vs beta** Graph endpoints confirmed in lab tenant.

---

## Verification (plan quality checklist)

- [x] Every task has acceptance criteria.
- [x] Every task has verification steps.
- [x] Dependencies explicit and ordered.
- [x] No task described as “implement everything.”
- [x] Checkpoints after foundation, validation, pack, core path, and completion.
- [x] Human approved `SPEC.md` **before** this execution plan (`SPEC.md` document control).

When implementation starts, prefer **checking off** tasks in `SPEC.md` **or** this file consistently — not both diverging.

# Project status (task log)

This document tracks **implementation task status** for the Intune drop-folder pipeline. For requirements and commands, see [SPEC.md](./SPEC.md). For dependency order and checkpoints, see [IMPLEMENTATION-PLAN.md](./IMPLEMENTATION-PLAN.md).

## Current tasks

**Task 11** (complete) — **Lab E2E validated (2026-04-09):** 7-Zip packaged via the drop folder, published through Graph, **installed on an Intune-enrolled device**. README checklist and env import path exercised successfully by the operator.

**Task 9–10** — `Invoke-IntuneDropInboxSweep` enumerates inbox `*.exe` / `*.msi` and runs `Invoke-IntuneDropForFile` per file (idempotent second pass when the inbox is empty). **`Process-Inbox.ps1 -Once`** is the explicit single-sweep entrypoint. **`Watch-Inbox.ps1`** uses a debounced **FileSystemWatcher** (Created / Changed / Renamed) instead of polling; for large installers, copy under a temporary name in `inbox/` then **rename** to the final `Vendor_AppName_x.y.z.*` so the watcher sees a complete file.

**Task 8** (complete) — Orchestrator: `Invoke-IntuneDropForFile` runs parse → allowlist → pack → Graph create/upload/assign → move the original installer to `done/`; failures after configuration load move to `failed/` with an optional `*.reason.txt`. Use `-NoAutoConnect` on `Invoke-IntuneDropForFile` when you already ran `Connect-IntuneDropGraphSession`.

**Task 7** (complete) — Microsoft Graph (**beta**): `Connect-IntuneDropGraphSession`, `New-IntuneDropWin32LobApp`, `Publish-IntuneDropWin32LobIntuneWinContent`, `New-IntuneDropWin32LobGroupAssignment`, `Disconnect-IntuneDropGraphSession`. Requires `Install-Module Microsoft.Graph` (see [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/powershell/microsoftgraph/installation)). App registration needs **Application** permission **DeviceManagementApps.ReadWrite.All** (admin consent). Graph failures surface **`ERR_GRAPH`**. Unit tests mock `Invoke-IntuneDropGraphRequest` / blob PUT.

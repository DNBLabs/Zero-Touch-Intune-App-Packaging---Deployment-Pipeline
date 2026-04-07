# Drop-folder Intune Win32 pipeline (convention-over-configuration)

Portfolio-oriented pipeline: operators **drop an `.exe` or `.msi` into one inbox folder**; PowerShell packs with **Win32 Content Prep**, uploads via **Microsoft Graph**, assigns to a **preconfigured test group**. Behavior is **predictable** because only **documented naming and silent-install patterns** are supported—everything else **fails loudly** with logs.

## Problem Statement

How might we let endpoint staff **drop an installer** and get a **packaged Win32 app in Intune** assigned to a **test group**—with **minimal steps**—without shipping **guessed** install strings or detection that **looks fine in the UI but breaks on devices**?

## Recommended Direction

**Option 1 — Convention over configuration:** one **inbox** folder, no mandatory sidecar files. A **strict filename convention** carries identity and version (for example `Vendor_AppName_1.2.3.exe`). The repo documents a **small allowlist of silent-switch patterns** per installer type (e.g. MSI vs specific EXE families used in the demo). The script **parses the filename**, maps to a **known pattern**, builds **install/uninstall/detection** deterministically, runs **IntuneWinAppUtil**, then **Graph**: create/update Win32 app, commit content, assign to **one test group ID** from environment or a single gitignored config.

**Portfolio angle:** the README/demo script states the hook—“**drop the file, it flows**”—and the **honest boundary**: unsupported names or unknown EXE families → **no assign**, log + optionally move to **`failed/`**. Secrets stay in **environment variables** (or gitignored config); the repo ships **`.env.example`** only.

## Key Assumptions to Validate

- [ ] **Filename convention** is sufficient for your demo apps (vendor strings, version parsing, no ambiguous names).
- [ ] **Silent install + detection** for each allowlisted pattern were tested on a **real test device** (not only “upload OK”).
- [ ] **Graph app registration** in a lab tenant has permissions for Win32 app lifecycle + **group assignment** on the target test group.
- [ ] **Win32 Content Prep** runs headless where you demo (path, prerequisites documented).
- [ ] **Update story** is defined: new drop = **new app** vs **update existing** (team picks one for v1 and documents it).

## MVP Scope

**In**

- Inbox folder + **documented naming rules** and **allowlisted install patterns**.
- PowerShell: validate → pack → upload → assign **test group**; **structured logging** (include Graph error detail in logs, not in user-facing generic messages).
- **Convention table in README** (examples: good filename → resulting install command summary).

**Out (for later)**

- Arbitrary vendor support without extending the convention table.
- Optional sidecar metadata files (can be Phase 2 if portfolio scope grows).
- Multi-ring production rollout beyond one test group.

## Not Doing (and Why)

- **Inferring silent switches for unknown EXEs** — destroys correctness; contradicts the portfolio story.
- **Requiring a UI or portal** — keeps the slice small and the demo obvious.
- **Hardcoding tenant IDs, client secrets, or group IDs in source** — security and maintainability; use env + examples only.

## Open Questions

- Which **1–2 real installers** will anchor the demo (so the allowlist is tiny and credible)?
- **Watcher** (FileSystemWatcher) vs **scheduled poll** (simpler to reason about in documentation)?
- Should successful runs **archive** packages to `done/` with timestamp for an easy before/after screenshot?

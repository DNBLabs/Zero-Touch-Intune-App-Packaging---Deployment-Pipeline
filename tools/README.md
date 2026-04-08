# Local tools (not committed)

## Load `.env` into PowerShell

PowerShell does **not** read `.env` by itself. From the **repository root**:

```powershell
pwsh -File .\tools\Import-IntuneDropEnv.ps1
```

Optional: `-LiteralPath 'C:\path\to\.env'`. Then run `Get-IntuneDropConfiguration` or `Process-Inbox.ps1` in the **same** session.

## Win32 Content Prep Tool

This pipeline needs **Microsoft Win32 Content Prep Tool** (`IntuneWinAppUtil.exe`) on the machine that runs the packaging step.

1. Download from Microsoft’s repo: [Microsoft-Win32-Content-Prep-Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool) (see also [Prepare a Win32 app](https://learn.microsoft.com/mem/intune/apps/apps-win32-prepare)).
2. Extract the archive locally—**do not commit** the executable to this repository.
3. Set `INTUNE_DROP_PREP_TOOL_EXE` in your `.env` file to the **full path** of `IntuneWinAppUtil.exe`.

This folder holds small helper scripts and this readme; large binaries stay out of version control.

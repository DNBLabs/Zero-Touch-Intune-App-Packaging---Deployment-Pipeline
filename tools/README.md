# Local tools (not committed)

## Win32 Content Prep Tool

This pipeline needs **Microsoft Win32 Content Prep Tool** (`IntuneWinAppUtil.exe`) on the machine that runs the packaging step.

1. Download the tool from Microsoft’s official distribution (search for **“Intune Win32 app packaging tool”** or use your tenant’s recommended link).
2. Extract the archive locally—**do not commit** the executable to this repository.
3. Set `INTUNE_DROP_PREP_TOOL_EXE` in your `.env` file to the **full path** of `IntuneWinAppUtil.exe`.

The repository intentionally keeps this folder empty except for this readme so installers stay out of version control.

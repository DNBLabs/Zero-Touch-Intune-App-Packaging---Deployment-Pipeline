<#
.SYNOPSIS
    Runs one pass over the configured inbox and invokes the full Intune drop pipeline per .exe/.msi file.
.DESCRIPTION
    Imports IntuneDropPipeline and calls Invoke-IntuneDropInboxSweep. You must pass -Once so operators explicitly choose a single sweep (continuous watching uses Watch-Inbox.ps1). A second run after files were moved to done/ or failed/ does not reprocess those installers because they are no longer in the inbox.
.PARAMETER Once
    Required. Processes all current *.exe / *.msi files in the inbox once, then exits. (Explicit -Once avoids an interactive prompt and matches the implementation plan.)
#>
[CmdletBinding()]
param(
    [switch] $Once
)

if (-not $Once) {
    throw 'Process-Inbox.ps1 requires -Once. Example: pwsh -File .\src\Process-Inbox.ps1 -Once'
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..'))
$dotEnvScript = Join-Path -Path $PSScriptRoot -ChildPath 'Import-IntuneDropRepoDotEnv.ps1'
& $dotEnvScript -RepositoryRoot $repoRoot

$moduleRoot = $PSScriptRoot
$manifestPath = Join-Path -Path $moduleRoot -ChildPath 'Modules\IntuneDropPipeline\IntuneDropPipeline.psd1'

Import-Module -Name $manifestPath -Force

Invoke-IntuneDropInboxSweep

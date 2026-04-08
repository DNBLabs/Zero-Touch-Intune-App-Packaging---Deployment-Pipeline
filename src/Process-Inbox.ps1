<#
.SYNOPSIS
    Runs one pass over the configured inbox and invokes the full Intune drop pipeline per .exe/.msi file.
.DESCRIPTION
    Imports IntuneDropPipeline, resolves paths from Get-IntuneDropConfiguration, and calls Invoke-IntuneDropForFile for each eligible file. Failures on one file do not stop remaining files. The -Once switch is kept for symmetry with documentation; each script invocation already performs a single sweep.
.PARAMETER Once
    Present for CLI compatibility; behavior is unchanged (every run is one sweep).
#>
[CmdletBinding()]
param(
    [switch] $Once
)

$moduleRoot = $PSScriptRoot
$manifestPath = Join-Path -Path $moduleRoot -ChildPath 'Modules\IntuneDropPipeline\IntuneDropPipeline.psd1'

Import-Module -Name $manifestPath -Force

$null = $Once

$configuration = Get-IntuneDropConfiguration
$extensions = @('.exe', '.msi')

Get-ChildItem -LiteralPath $configuration.InboxPath -File -ErrorAction SilentlyContinue |
    Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() } |
    ForEach-Object {
        try {
            Invoke-IntuneDropForFile -LiteralPath $_.FullName
        }
        catch {
            Write-Error -ErrorRecord $PSItem
        }
    }

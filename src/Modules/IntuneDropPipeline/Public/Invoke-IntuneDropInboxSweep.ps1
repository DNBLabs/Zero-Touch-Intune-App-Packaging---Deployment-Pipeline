<#
.SYNOPSIS
    Enumerates allowlisted installers in the configured inbox and runs Invoke-IntuneDropForFile for each.
.DESCRIPTION
    Resolves paths via Get-IntuneDropConfiguration, lists *.exe and *.msi (case-insensitive extension), and invokes the orchestrator per file. Errors from one file are written with Write-Error and do not stop remaining files.
.OUTPUTS
    None. Failed files are moved by Invoke-IntuneDropForFile when configuration was loaded successfully there.
#>
function Invoke-IntuneDropInboxSweep {
    [CmdletBinding()]
    param()

    $configuration = Get-IntuneDropConfiguration
    Write-IntuneDropLog -Level Info -Message (
        "Configuration: inbox '{0}', staging '{1}'." -f $configuration.InboxPath, $configuration.StagingPath
    ) -RuleId 'CONFIG_PATHS'
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
}

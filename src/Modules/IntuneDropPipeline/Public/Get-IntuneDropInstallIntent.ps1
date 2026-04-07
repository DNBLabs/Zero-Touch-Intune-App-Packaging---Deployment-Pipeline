<#
.SYNOPSIS
    Maps a parsed drop package to install, uninstall, and detection details using the committed allowlist.
.DESCRIPTION
    Reads Data\IntuneDropAllowlist.json from the module. The first matching row for the package extension (and optional vendor/app filters on the row) wins. MSI uninstall lines keep {ProductCode} until a product code is supplied via -ProductCode.
.PARAMETER Package
    Object produced by Get-IntuneDropPackageFromFileName (Vendor, AppName, Version, Extension, FileName).
.PARAMETER ProductCode
    Optional MSI product code (GUID) used to expand {ProductCode} in templates and in detection when applicable.
.OUTPUTS
    IntuneDrop.InstallIntent custom object with DisplayName, InstallCommandLine, UninstallCommandLine, Detection, and metadata.
.EXAMPLE
    $p = Get-IntuneDropPackageFromFileName -FileName 'Contoso_App_1.0.0.msi'
    Get-IntuneDropInstallIntent -Package $p
#>
function Get-IntuneDropInstallIntent {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $Package,

        [Parameter()]
        [string] $ProductCode
    )

    $requiredProperties = @('Vendor', 'AppName', 'Version', 'Extension', 'FileName')
    foreach ($prop in $requiredProperties) {
        if (-not ($Package.PSObject.Properties.Name -contains $prop)) {
            throw "Package is missing required property '$prop'. Run Get-IntuneDropPackageFromFileName first."
        }
    }

    $moduleBasePath = Split-Path -Path $PSScriptRoot -Parent
    $entries = Get-IntuneDropAllowlistEntries -ModuleBasePath $moduleBasePath
    $entry = Resolve-IntuneDropAllowlistMatch -Entries $entries -Package $Package

    if ($null -eq $entry) {
        $detail = "No allowlist entry matches extension '{0}' for vendor '{1}' and app '{2}'." -f $Package.Extension, $Package.Vendor, $Package.AppName
        $record = New-IntuneDropAllowlistErrorRecord -Message $detail -TargetObject $Package
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $installLine = Expand-IntuneDropTemplate -Template ([string]$entry.installCommandTemplate) -Package $Package -ProductCode $ProductCode
    $uninstallLine = Expand-IntuneDropTemplate -Template ([string]$entry.uninstallCommandTemplate) -Package $Package -ProductCode $ProductCode
    $displayName = Expand-IntuneDropTemplate -Template ([string]$entry.displayNameTemplate) -Package $Package -ProductCode $ProductCode
    $detection = ConvertTo-IntuneDropDetectionSpec -Detection $entry.detection -Package $Package -ProductCode $ProductCode

    [pscustomobject]@{
        PSTypeName         = 'IntuneDrop.InstallIntent'
        AllowlistEntryId   = $entry.id
        Description        = [string]$entry.description
        DisplayName        = $displayName
        InstallCommandLine = $installLine
        UninstallCommandLine = $uninstallLine
        Detection          = $detection
        Package            = $Package
    }
}

<#
.SYNOPSIS
    Selects the first allowlist entry matching the parsed package extension and optional vendor/app filters.
.PARAMETER Entries
    Collection of entry objects from IntuneDropAllowlist.json.
.PARAMETER Package
    Output of Get-IntuneDropPackageFromFileName (Vendor, AppName, Version, Extension, FileName).
#>
function Resolve-IntuneDropAllowlistMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable] $Entries,

        [Parameter(Mandatory)]
        [object] $Package
    )

    foreach ($entry in $Entries) {
        $matchBlock = $entry.match
        if ($null -eq $matchBlock) { continue }

        $ext = [string]$matchBlock.extension
        if ([string]::IsNullOrWhiteSpace($ext)) { continue }
        if ($ext.ToLowerInvariant() -ne [string]$Package.Extension.ToLowerInvariant()) {
            continue
        }

        $matchVendor = $matchBlock.vendor
        if ($null -ne $matchVendor -and [string]$matchVendor -ne '') {
            if (-not [string]::Equals([string]$matchVendor, [string]$Package.Vendor, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
        }

        $matchApp = $matchBlock.appName
        if ($null -ne $matchApp -and [string]$matchApp -ne '') {
            if (-not [string]::Equals([string]$matchApp, [string]$Package.AppName, [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
        }

        return $entry
    }

    return $null
}

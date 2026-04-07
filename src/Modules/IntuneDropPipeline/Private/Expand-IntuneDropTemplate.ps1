<#
.SYNOPSIS
    Replaces {InstallerFileName}, {Vendor}, {AppName}, {Version}, and {ProductCode} tokens in a template string.
.PARAMETER Template
    Text containing optional placeholders.
.PARAMETER Package
    Parsed package object (Vendor, AppName, Version, FileName).
.PARAMETER ProductCode
    Optional MSI product GUID string; when omitted, {ProductCode} is left unchanged.
#>
function Expand-IntuneDropTemplate {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Template,

        [Parameter(Mandatory)]
        [object] $Package,

        [Parameter()]
        [string] $ProductCode
    )

    $result = $Template
    $result = $result.Replace('{InstallerFileName}', [string]$Package.FileName)
    $result = $result.Replace('{Vendor}', [string]$Package.Vendor)
    $result = $result.Replace('{AppName}', [string]$Package.AppName)
    $result = $result.Replace('{Version}', [string]$Package.Version)
    if (-not [string]::IsNullOrEmpty($ProductCode)) {
        $result = $result.Replace('{ProductCode}', $ProductCode)
    }

    return $result
}

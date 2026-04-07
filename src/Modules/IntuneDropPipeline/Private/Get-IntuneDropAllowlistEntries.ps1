<#
.SYNOPSIS
    Loads committed allowlist entries from IntuneDropAllowlist.json next to the module root.
.PARAMETER ModuleBasePath
    Absolute path to the IntuneDropPipeline module folder (contains Data and Public).
.OUTPUTS
    System.Collections.ArrayList of PSCustomObject rows ( deserialized entry objects ).
#>
function Get-IntuneDropAllowlistEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $ModuleBasePath
    )

    $dataFile = Join-Path -Path $ModuleBasePath -ChildPath 'Data\IntuneDropAllowlist.json'
    if (-not (Test-Path -LiteralPath $dataFile)) {
        throw "Allowlist file not found at '$dataFile'."
    }

    try {
        $raw = Get-Content -LiteralPath $dataFile -Raw -Encoding utf8 -ErrorAction Stop
        $document = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to read allowlist JSON at '$dataFile': $($_.Exception.Message)"
    }

    if ($null -eq $document.entries) {
        throw "Allowlist document is missing the 'entries' array in '$dataFile'."
    }

    return $document.entries
}

<#
.SYNOPSIS
    Builds an ErrorRecord for allowlist lookup failures (unknown extension or non-matching vendor/app row).
.PARAMETER Message
    Detail text after the ERR_ALLOWLIST prefix (no secrets).
.PARAMETER TargetObject
    Optional object related to the failure (often the package or extension).
#>
function New-IntuneDropAllowlistErrorRecord {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter()]
        [object] $TargetObject
    )

    $fullMessage = 'ERR_ALLOWLIST: {0}' -f $Message
    $exception = [System.InvalidOperationException]::new($fullMessage)
    return [System.Management.Automation.ErrorRecord]::new(
        $exception,
        'ERR_ALLOWLIST',
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $TargetObject
    )
}

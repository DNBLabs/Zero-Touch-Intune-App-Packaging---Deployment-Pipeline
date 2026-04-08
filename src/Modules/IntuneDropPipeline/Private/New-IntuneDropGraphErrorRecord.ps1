<#
.SYNOPSIS
    Builds an ErrorRecord for Microsoft Graph or IntuneWin upload failures.
.PARAMETER Message
    Detail after the ERR_GRAPH prefix (no tokens or secrets).
.PARAMETER TargetObject
    Optional diagnostic context (request URI fragment or path).
#>
function New-IntuneDropGraphErrorRecord {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter()]
        [object] $TargetObject
    )

    $fullMessage = 'ERR_GRAPH: {0}' -f $Message
    $exception = [System.InvalidOperationException]::new($fullMessage)
    return [System.Management.Automation.ErrorRecord]::new(
        $exception,
        'ERR_GRAPH',
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $TargetObject
    )
}

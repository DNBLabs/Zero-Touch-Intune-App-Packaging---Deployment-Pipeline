<#
.SYNOPSIS
    Builds an ErrorRecord for MSI metadata failures (COM unavailable, unreadable database, missing ProductCode).
.PARAMETER Message
    Detail after the ERR_MSI_METADATA prefix (no secrets).
.PARAMETER TargetObject
    Path or object related to the failure.
#>
function New-IntuneDropMsiMetadataErrorRecord {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter()]
        [object] $TargetObject
    )

    $fullMessage = 'ERR_MSI_METADATA: {0}' -f $Message
    $exception = [System.InvalidOperationException]::new($fullMessage)
    return [System.Management.Automation.ErrorRecord]::new(
        $exception,
        'ERR_MSI_METADATA',
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $TargetObject
    )
}

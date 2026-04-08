<#
.SYNOPSIS
    Builds an ErrorRecord for Win32 Content Prep Tool failures.
.PARAMETER Message
    Detail after the ERR_PACKAGING prefix (no secrets; may reference log file paths).
.PARAMETER TargetObject
    Context object for diagnostics (often the installer path or job folder).
#>
function New-IntuneDropPackagingErrorRecord {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter()]
        [object] $TargetObject
    )

    $fullMessage = 'ERR_PACKAGING: {0}' -f $Message
    $exception = [System.InvalidOperationException]::new($fullMessage)
    return [System.Management.Automation.ErrorRecord]::new(
        $exception,
        'ERR_PACKAGING',
        [System.Management.Automation.ErrorCategory]::InvalidOperation,
        $TargetObject
    )
}

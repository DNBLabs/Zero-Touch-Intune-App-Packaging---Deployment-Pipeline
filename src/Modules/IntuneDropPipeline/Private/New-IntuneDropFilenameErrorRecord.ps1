<#
.SYNOPSIS
    Builds an ErrorRecord for filename convention violations with a stable FullyQualifiedErrorId.
.PARAMETER Message
    Human-readable detail after the ERR_FILENAME_CONVENTION prefix (no secrets).
.PARAMETER TargetObject
    The file name or path supplied by the caller for diagnostic context.
#>
function New-IntuneDropFilenameErrorRecord {
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter()]
        [object] $TargetObject
    )

    $fullMessage = 'ERR_FILENAME_CONVENTION: {0}' -f $Message
    $exception = [System.ArgumentException]::new($fullMessage)
    return [System.Management.Automation.ErrorRecord]::new(
        $exception,
        'ERR_FILENAME_CONVENTION',
        [System.Management.Automation.ErrorCategory]::InvalidArgument,
        $TargetObject
    )
}

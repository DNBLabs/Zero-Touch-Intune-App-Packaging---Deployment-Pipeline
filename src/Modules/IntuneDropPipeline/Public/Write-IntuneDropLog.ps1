<#
.SYNOPSIS
    Writes a single structured log line for the Intune drop pipeline.
.PARAMETER Level
    Severity label used in log output.
.PARAMETER Message
    Human-readable message text; must not contain secrets.
.PARAMETER RuleId
    Optional stable rule or error code (for example ERR_FILENAME_CONVENTION).
.OUTPUTS
    None. Emits to the information stream for downstream redirection or logging hosts.
#>
function Write-IntuneDropLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string] $Level,

        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter()]
        [string] $RuleId
    )

    $timestampUtc = (Get-Date).ToUniversalTime().ToString('o')
    $ruleSegment = if ($RuleId) { "[$RuleId] " } else { '' }
    $line = '{0} [{1}] {2}{3}' -f $timestampUtc, $Level, $ruleSegment, $Message

    Write-Information -MessageData $line -InformationAction Continue
}

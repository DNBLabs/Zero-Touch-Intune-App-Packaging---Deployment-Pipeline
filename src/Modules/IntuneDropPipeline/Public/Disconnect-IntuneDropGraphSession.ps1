<#
.SYNOPSIS
    Disconnects the current Microsoft Graph session created by Connect-IntuneDropGraphSession.
#>
function Disconnect-IntuneDropGraphSession {
    [CmdletBinding()]
    param()

    if (-not (Get-Command -Name Disconnect-MgGraph -ErrorAction SilentlyContinue)) {
        return
    }

    $context = Get-MgContext -ErrorAction SilentlyContinue
    if ($null -eq $context) {
        return
    }

    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
}

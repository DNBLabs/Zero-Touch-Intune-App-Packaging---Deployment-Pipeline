<#
.SYNOPSIS
    Returns the current Microsoft Graph session context, or $null when the auth module is unavailable or no session exists.
.DESCRIPTION
    Loads Microsoft.Graph.Authentication with SilentlyContinue so hosts without the SDK still load the module; downstream commands handle a missing session. Centralizes session detection so Pester can mock a single internal function.
.OUTPUTS
    The object returned by Get-MgContext, or $null.
#>
function Get-IntuneDropMgContext {
    [CmdletBinding()]
    [OutputType([object])]
    param()

    Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
    return Get-MgContext -ErrorAction SilentlyContinue
}

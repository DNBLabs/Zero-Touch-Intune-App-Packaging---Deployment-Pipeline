<#
.SYNOPSIS
    Uploads an .intunewin to Intune for an existing win32LobApp (content version, Azure blob upload, commit, patch committedContentVersion).
.DESCRIPTION
    Orchestrates the Graph v1.0 Win32 LOB content flow: create content version, create file placeholder, wait for SAS URI, PUT blob, commit encryption info, wait for Intune validation, PATCH app with committedContentVersion. Requires Connect-IntuneDropGraphSession and appropriate application permissions.
.PARAMETER MobileAppId
    Target Intune application ID.
.PARAMETER IntuneWinPath
    Path to the packaged .intunewin file.
#>
function Publish-IntuneDropWin32LobIntuneWinContent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $MobileAppId,

        [Parameter(Mandatory)]
        [string] $IntuneWinPath,

        [Parameter()]
        [int] $AzureUriPollSeconds,

        [Parameter()]
        [int] $AzureUriMaxAttempts,

        [Parameter()]
        [int] $CommitPollSeconds,

        [Parameter()]
        [int] $CommitMaxAttempts
    )

    $completeParams = @{
        MobileAppId   = $MobileAppId
        IntuneWinPath = $IntuneWinPath
    }
    if ($PSBoundParameters.ContainsKey('AzureUriPollSeconds')) {
        $completeParams['AzureUriPollSeconds'] = $AzureUriPollSeconds
    }
    if ($PSBoundParameters.ContainsKey('AzureUriMaxAttempts')) {
        $completeParams['AzureUriMaxAttempts'] = $AzureUriMaxAttempts
    }
    if ($PSBoundParameters.ContainsKey('CommitPollSeconds')) {
        $completeParams['CommitPollSeconds'] = $CommitPollSeconds
    }
    if ($PSBoundParameters.ContainsKey('CommitMaxAttempts')) {
        $completeParams['CommitMaxAttempts'] = $CommitMaxAttempts
    }

    return Complete-IntuneDropWin32LobIntuneWinUpload @completeParams
}

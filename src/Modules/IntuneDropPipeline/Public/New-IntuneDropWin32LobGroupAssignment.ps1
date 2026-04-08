<#
.SYNOPSIS
    Assigns a Win32 LOB mobile app to an Entra ID group with installIntent required.
.DESCRIPTION
    POSTs to Graph beta mobileAppAssignment. The intent property uses the installIntent enum (required, available, uninstall, availableWithoutEnrollment), not mobileAppEnforcementIntentType values such as requiredInstall, which apply to mobileAppAssignmentDetail and cause 400 ModelValidationFailure.
.PARAMETER MobileAppId
    The Intune mobile app ID returned from New-IntuneDropWin32LobApp.
.PARAMETER GroupId
    Entra ID group object ID (same value as INTUNE_DROP_TEST_GROUP_ID).
#>
function New-IntuneDropWin32LobGroupAssignment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $MobileAppId,

        [Parameter(Mandatory)]
        [string] $GroupId
    )

    $assignmentUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$MobileAppId/assignments"
    $assignmentBody = [ordered]@{
        '@odata.type' = '#microsoft.graph.mobileAppAssignment'
        'intent'      = 'required'
        'target'      = [ordered]@{
            '@odata.type' = '#microsoft.graph.groupAssignmentTarget'
            'groupId'     = $GroupId
        }
    }

    return Invoke-IntuneDropGraphRequest -Method POST -Uri $assignmentUri -Body $assignmentBody
}

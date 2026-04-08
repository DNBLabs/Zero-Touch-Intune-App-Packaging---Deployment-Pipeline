<#
.SYNOPSIS
    Creates a win32LobApp object in Intune via Microsoft Graph beta APIs.
.DESCRIPTION
    Combines install intent from the allowlist with IntuneWin metadata (setup file name, size, encryption profile) to POST /deviceAppManagement/mobileApps. You must connect with Connect-IntuneDropGraphSession first and grant DeviceManagementApps.ReadWrite.All (application permission with admin consent).
.PARAMETER InstallIntent
    Output from Get-IntuneDropInstallIntent. For MSI packages, include a populated ProductCode on Detection before calling this command.
.PARAMETER IntuneWinPath
    Full path to the .intunewin file produced by New-IntuneDropWin32Package.
.OUTPUTS
    Object with Id and Raw response payload.
#>
function New-IntuneDropWin32LobApp {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [object] $InstallIntent,

        [Parameter(Mandatory)]
        [string] $IntuneWinPath
    )

    $metadata = Get-IntuneDropIntuneWinPackageMetadata -Path $IntuneWinPath
    $fileItem = Get-Item -LiteralPath $metadata.IntuneWinPath -ErrorAction Stop

    $createBody = ConvertTo-IntuneDropWin32LobCreateBody `
        -InstallIntent $InstallIntent `
        -IntuneWinMetadata $metadata `
        -IntuneWinFileName $fileItem.Name `
        -IntuneWinFileLengthBytes $fileItem.Length

    $createUri = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'
    $response = Invoke-IntuneDropGraphRequest -Method POST -Uri $createUri -Body $createBody

    [pscustomobject]@{
        PSTypeName = 'IntuneDrop.Win32LobAppCreated'
        Id         = [string]($response.id ?? $response.Id)
        Raw        = $response
    }
}

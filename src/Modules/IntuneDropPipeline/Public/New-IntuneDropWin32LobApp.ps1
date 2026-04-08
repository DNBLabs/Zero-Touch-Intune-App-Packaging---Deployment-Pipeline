<#
.SYNOPSIS
    Creates a win32LobApp object in Intune via Microsoft Graph.
.DESCRIPTION
    POSTs to Graph v1.0 /deviceAppManagement/mobileApps (Microsoft recommends v1 for Intune over beta). Content upload, commit, and some assignments still use beta endpoints elsewhere in this module. Combine with IntuneWin metadata from packaging. Call Connect-IntuneDropGraphSession first with DeviceManagementApps.ReadWrite.All (app permission + admin consent).
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

    $createUri = 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps'
    $response = Invoke-IntuneDropGraphRequest -Method POST -Uri $createUri -Body $createBody

    [pscustomobject]@{
        PSTypeName = 'IntuneDrop.Win32LobAppCreated'
        Id         = [string]($response.id ?? $response.Id)
        Raw        = $response
    }
}

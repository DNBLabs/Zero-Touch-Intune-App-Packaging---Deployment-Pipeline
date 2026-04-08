<#
.SYNOPSIS
    Creates a Win32 LOB content version, uploads the .intunewin via SAS URI, commits the file, and marks the version committed on the app.
#>
function Complete-IntuneDropWin32LobIntuneWinUpload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $MobileAppId,

        [Parameter(Mandatory)]
        [string] $IntuneWinPath,

        [Parameter()]
        [int] $AzureUriPollSeconds = 2,

        [Parameter()]
        [int] $AzureUriMaxAttempts = 30,

        [Parameter()]
        [int] $CommitPollSeconds = 3,

        [Parameter()]
        [int] $CommitMaxAttempts = 40
    )

    $metadata = Get-IntuneDropIntuneWinPackageMetadata -Path $IntuneWinPath
    $fileItem = Get-Item -LiteralPath $metadata.IntuneWinPath
    $leaf = $fileItem.Name
    $graphBase = 'https://graph.microsoft.com/beta/deviceAppManagement/mobileApps'

    $versionUri = "$graphBase/$MobileAppId/microsoft.graph.win32LobApp/contentVersions"
    $versionResponse = Invoke-IntuneDropGraphRequest -Method POST -Uri $versionUri -Body ([ordered]@{})
    $versionId = [string]($versionResponse.id ?? $versionResponse.Id)

    $unencryptedSize = $metadata.UnencryptedContentSize
    if ($null -eq $unencryptedSize) {
        $unencryptedSize = $fileItem.Length
    }

    $fileCreateBody = [ordered]@{
        '@odata.type'   = '#microsoft.graph.mobileAppContentFile'
        'name'          = $leaf
        'size'          = [long]$unencryptedSize
        'sizeEncrypted' = [long]$fileItem.Length
        'isDependency'  = $false
    }

    $filesUri = "$graphBase/$MobileAppId/microsoft.graph.win32LobApp/contentVersions/$versionId/files"
    $fileResponse = Invoke-IntuneDropGraphRequest -Method POST -Uri $filesUri -Body $fileCreateBody
    $fileId = [string]($fileResponse.id ?? $fileResponse.Id)

    $fileInstanceUri = "$filesUri/$fileId"
    $sasUri = $null
    for ($attempt = 0; $attempt -lt $AzureUriMaxAttempts; $attempt++) {
        $fileState = Invoke-IntuneDropGraphRequest -Method GET -Uri $fileInstanceUri
        $sasUri = [string]$fileState.azureStorageUri
        if (-not [string]::IsNullOrWhiteSpace($sasUri)) {
            break
        }
        Start-Sleep -Seconds $AzureUriPollSeconds
    }

    if ([string]::IsNullOrWhiteSpace($sasUri)) {
        $record = New-IntuneDropGraphErrorRecord -Message 'Timed out waiting for Azure SAS URI from Intune.' -TargetObject $fileInstanceUri
        $PSCmdlet.ThrowTerminatingError($record)
    }

    Invoke-IntuneDropAzureBlobSinglePut -SasUri $sasUri -FilePath $fileItem.FullName

    $commitUri = "$fileInstanceUri/commit"
    $commitBody = [ordered]@{
        'fileEncryptionInfo' = $metadata.FileEncryptionInfo
    }
    Invoke-IntuneDropGraphRequest -Method POST -Uri $commitUri -Body $commitBody | Out-Null

    $committed = $false
    for ($attempt = 0; $attempt -lt $CommitMaxAttempts; $attempt++) {
        $fileState = Invoke-IntuneDropGraphRequest -Method GET -Uri $fileInstanceUri
        if ($fileState.isCommitted -eq $true) {
            $committed = $true
            break
        }
        $state = [string]$fileState.uploadState
        if ($state -match 'commitFileFailed|error') {
            $record = New-IntuneDropGraphErrorRecord -Message "Intune reported upload state '$state' while waiting for commit." -TargetObject $fileInstanceUri
            $PSCmdlet.ThrowTerminatingError($record)
        }
        Start-Sleep -Seconds $CommitPollSeconds
    }

    if (-not $committed) {
        $record = New-IntuneDropGraphErrorRecord -Message 'Timed out waiting for Intune to commit the Win32 content file.' -TargetObject $fileInstanceUri
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $patchUri = "$graphBase/$MobileAppId"
    $patchBody = [ordered]@{
        '@odata.type'             = '#microsoft.graph.win32LobApp'
        'committedContentVersion' = $versionId
    }
    Invoke-IntuneDropGraphRequest -Method PATCH -Uri $patchUri -Body $patchBody | Out-Null

    [pscustomobject]@{
        MobileAppId             = $MobileAppId
        CommittedContentVersion = $versionId
        ContentFileId           = $fileId
        IntuneWinPath           = $fileItem.FullName
    }
}

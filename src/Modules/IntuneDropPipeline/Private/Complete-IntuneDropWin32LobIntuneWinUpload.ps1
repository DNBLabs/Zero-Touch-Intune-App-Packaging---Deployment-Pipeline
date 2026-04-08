<#
.SYNOPSIS
    Creates a Win32 LOB content version, uploads the .intunewin via SAS URI, commits the file, and marks the version committed on the app.
.DESCRIPTION
    Uses Graph v1.0 with the typed LOB segment microsoft.graph.mobileLobApp before contentVersions and files (required for win32LobApp; POST .../mobileApps/{id}/contentVersions without the cast returns 400 Resource not found for the segment contentVersions). The commit action body must include fileEncryptionInfo with @odata.type #microsoft.graph.fileEncryptionInfo or Intune may leave the file in commitFileFailed. ZIP-wrapped packages upload only IntuneWinPackage/Contents/IntunePackage.intunewin bytes to Azure so the blob length matches mobileAppContentFile.sizeEncrypted; legacy packages upload the entire .intunewin file.
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
    $graphBase = 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps'
    $lobContentRoot = "$graphBase/$MobileAppId/microsoft.graph.mobileLobApp"

    $versionUri = "$lobContentRoot/contentVersions"
    $versionResponse = Invoke-IntuneDropGraphRequest -Method POST -Uri $versionUri -Body ([ordered]@{
            '@odata.type' = '#microsoft.graph.mobileAppContent'
        })
    $versionId = [string]($versionResponse.id ?? $versionResponse.Id)

    $unencryptedSize = $metadata.UnencryptedContentSize
    if ($null -eq $unencryptedSize) {
        $unencryptedSize = $fileItem.Length
    }

    $sizeEncrypted = $metadata.EncryptedContentSize
    if ($null -eq $sizeEncrypted) {
        $sizeEncrypted = [long]$fileItem.Length
    }

    $fileCreateBody = [ordered]@{
        '@odata.type'     = '#microsoft.graph.mobileAppContentFile'
        'name'            = $leaf
        'size'            = [long]$unencryptedSize
        'sizeEncrypted'   = [long]$sizeEncrypted
        'isDependency'    = $false
    }

    $filesUri = "$lobContentRoot/contentVersions/$versionId/files"
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

    $blobUploadPath = $fileItem.FullName
    $blobUploadTempPath = $null
    if ($metadata.PackageLayout -eq 'Zip' -and $null -ne $metadata.EncryptedContentSize) {
        $blobUploadTempPath = Export-IntuneDropIntuneWinZipEncryptedPayloadToTemp -SourcePath $fileItem.FullName
        $blobUploadPath = $blobUploadTempPath
    }

    try {
        Invoke-IntuneDropAzureBlobSinglePut -SasUri $sasUri -FilePath $blobUploadPath
    }
    finally {
        if ($null -ne $blobUploadTempPath -and (Test-Path -LiteralPath $blobUploadTempPath)) {
            Remove-Item -LiteralPath $blobUploadTempPath -Force -ErrorAction SilentlyContinue
        }
    }

    $commitUri = "$fileInstanceUri/commit"
    $srcFei = $metadata.FileEncryptionInfo
    $commitBody = [ordered]@{
        'fileEncryptionInfo' = [ordered]@{
            '@odata.type'          = '#microsoft.graph.fileEncryptionInfo'
            'encryptionKey'        = [string]$srcFei.encryptionKey
            'macKey'               = [string]$srcFei.macKey
            'initializationVector' = [string]$srcFei.initializationVector
            'mac'                  = [string]$srcFei.mac
            'profileIdentifier'    = [string]$srcFei.profileIdentifier
            'fileDigest'           = [string]$srcFei.fileDigest
            'fileDigestAlgorithm'  = [string]$srcFei.fileDigestAlgorithm
        }
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
            $detail = "uploadState=$state; name=$([string]$fileState.name); size=$([string]$fileState.size); sizeEncrypted=$([string]$fileState.sizeEncrypted)."
            $record = New-IntuneDropGraphErrorRecord -Message "Intune reported upload state '$state' while waiting for commit. $detail" -TargetObject $fileInstanceUri
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

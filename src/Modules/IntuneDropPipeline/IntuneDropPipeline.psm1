<#
.SYNOPSIS
    IntuneDropPipeline module — configuration and logging for the zero-touch Win32 drop-folder pipeline.
.DESCRIPTION
    Provides configuration, parsing, allowlisted install intent, MSI metadata (Windows), IntuneWin packaging, Microsoft Graph publish flows, and structured logging.
#>

$privateDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
$privateScriptLoadOrder = @(
    'New-IntuneDropFilenameErrorRecord.ps1'
    'New-IntuneDropAllowlistErrorRecord.ps1'
    'New-IntuneDropMsiMetadataErrorRecord.ps1'
    'New-IntuneDropPackagingErrorRecord.ps1'
    'New-IntuneDropGraphErrorRecord.ps1'
    'Get-IntuneDropIntuneWinPackageMetadata.ps1'
    'Get-IntuneDropMgContext.ps1'
    'Invoke-IntuneDropGraphRequest.ps1'
    'Invoke-IntuneDropAzureBlobSinglePut.ps1'
    'ConvertTo-IntuneDropWin32LobCreateBody.ps1'
    'Complete-IntuneDropWin32LobIntuneWinUpload.ps1'
    'Invoke-IntuneDropIntuneWinAppUtilProcess.ps1'
    'Get-IntuneDropRepositoryRoot.ps1'
    'Resolve-IntuneDropManagedPaths.ps1'
    'Get-IntuneDropAllowlistEntries.ps1'
    'Expand-IntuneDropTemplate.ps1'
    'ConvertTo-IntuneDropDetectionSpec.ps1'
    'Resolve-IntuneDropAllowlistMatch.ps1'
    'Move-IntuneDropInstallerToOutcomeFolder.ps1'
)

foreach ($privateFileName in $privateScriptLoadOrder) {
    $privatePath = Join-Path -Path $privateDirectory -ChildPath $privateFileName
    if (-not (Test-Path -LiteralPath $privatePath)) {
        throw "Required private script missing: '$privatePath'"
    }
    . $privatePath
}

$publicScripts = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction Stop | Sort-Object -Property Name
foreach ($script in $publicScripts) {
    . $script.FullName
}

Export-ModuleMember -Function @(
    'Connect-IntuneDropGraphSession'
    'Disconnect-IntuneDropGraphSession'
    'Get-IntuneDropConfiguration'
    'Get-IntuneDropInstallIntent'
    'Get-IntuneDropMsiProductCode'
    'Get-IntuneDropPackageFromFileName'
    'Invoke-IntuneDropForFile'
    'Invoke-IntuneDropInboxSweep'
    'New-IntuneDropWin32LobApp'
    'New-IntuneDropWin32LobGroupAssignment'
    'New-IntuneDropWin32Package'
    'Publish-IntuneDropWin32LobIntuneWinContent'
    'Write-IntuneDropLog'
)

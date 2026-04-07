<#
.SYNOPSIS
    IntuneDropPipeline module — configuration and logging for the zero-touch Win32 drop-folder pipeline.
.DESCRIPTION
    Provides Get-IntuneDropConfiguration, Get-IntuneDropPackageFromFileName, Get-IntuneDropInstallIntent (allowlisted install/detection), and Write-IntuneDropLog.
#>

$privateDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
$privateScriptLoadOrder = @(
    'New-IntuneDropFilenameErrorRecord.ps1'
    'New-IntuneDropAllowlistErrorRecord.ps1'
    'Get-IntuneDropRepositoryRoot.ps1'
    'Resolve-IntuneDropManagedPaths.ps1'
    'Get-IntuneDropAllowlistEntries.ps1'
    'Expand-IntuneDropTemplate.ps1'
    'ConvertTo-IntuneDropDetectionSpec.ps1'
    'Resolve-IntuneDropAllowlistMatch.ps1'
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
    'Get-IntuneDropConfiguration'
    'Get-IntuneDropInstallIntent'
    'Get-IntuneDropPackageFromFileName'
    'Write-IntuneDropLog'
)

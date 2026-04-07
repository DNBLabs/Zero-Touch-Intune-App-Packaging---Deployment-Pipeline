<#
.SYNOPSIS
    IntuneDropPipeline module — configuration and logging for the zero-touch Win32 drop-folder pipeline.
.DESCRIPTION
    Provides Get-IntuneDropConfiguration, Get-IntuneDropPackageFromFileName (filename convention validation), and Write-IntuneDropLog.
#>

$privateScripts = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -File -ErrorAction Stop
foreach ($script in $privateScripts) {
    . $script.FullName
}

$publicScripts = Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -File -ErrorAction Stop
foreach ($script in $publicScripts) {
    . $script.FullName
}

Export-ModuleMember -Function @(
    'Get-IntuneDropConfiguration',
    'Get-IntuneDropPackageFromFileName',
    'Write-IntuneDropLog'
)

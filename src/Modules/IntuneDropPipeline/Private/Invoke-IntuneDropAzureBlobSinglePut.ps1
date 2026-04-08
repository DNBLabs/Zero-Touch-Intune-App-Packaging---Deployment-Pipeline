<#
.SYNOPSIS
    Uploads a local file to Azure Blob Storage using a SAS URL returned by Intune.
#>
function Invoke-IntuneDropAzureBlobSinglePut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $SasUri,

        [Parameter(Mandatory)]
        [string] $FilePath
    )

    try {
        Microsoft.PowerShell.Utility\Invoke-WebRequest `
            -Uri $SasUri `
            -Method Put `
            -InFile $FilePath `
            -Headers @{ 'x-ms-blob-type' = 'BlockBlob' } `
            -UseBasicParsing `
            -ErrorAction Stop | Out-Null
    }
    catch {
        $record = New-IntuneDropGraphErrorRecord -Message "Azure blob upload failed: $($_.Exception.Message)" -TargetObject $SasUri
        $PSCmdlet.ThrowTerminatingError($record)
    }
}

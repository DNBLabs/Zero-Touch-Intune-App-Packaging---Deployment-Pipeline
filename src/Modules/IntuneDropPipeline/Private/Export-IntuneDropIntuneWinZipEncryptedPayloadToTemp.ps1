<#
.SYNOPSIS
    Extracts IntuneWinPackage/Contents/IntunePackage.intunewin from a ZIP-wrapped .intunewin to a temp file for Azure upload.
.DESCRIPTION
    Graph expects the Win32 LOB blob to contain exactly sizeEncrypted bytes matching Detection.xml encryption metadata. That payload is the inner archive entry, not the outer ZIP wrapper. Legacy .intunewin (non-ZIP) does not use this path.
.PARAMETER SourcePath
    Full path to the outer .intunewin file.
.OUTPUTS
    Full path to a temporary file holding the raw encrypted bytes. Caller must delete the file after upload.
#>
function Export-IntuneDropIntuneWinZipEncryptedPayloadToTemp {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $SourcePath
    )

    $resolved = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
    $zip = [System.IO.Compression.ZipFile]::OpenRead($resolved)
    try {
        $encryptedEntry = $null
        foreach ($entry in $zip.Entries) {
            $normalized = $entry.FullName -replace '\\', '/'
            if ($normalized -match '(?i)^IntuneWinPackage/Contents/IntunePackage\.intunewin$') {
                $encryptedEntry = $entry
                break
            }
        }
        if ($null -eq $encryptedEntry) {
            foreach ($entry in $zip.Entries) {
                $normalized = $entry.FullName -replace '\\', '/'
                if ($normalized -match '(?i)^IntuneWinPackage/Contents/[^/]+\.intunewin$') {
                    $encryptedEntry = $entry
                    break
                }
            }
        }
        if ($null -eq $encryptedEntry) {
            $record = New-IntuneDropGraphErrorRecord -Message 'ZIP .intunewin has no IntuneWinPackage/Contents/IntunePackage.intunewin entry; cannot build the Azure upload payload.' -TargetObject $resolved
            $PSCmdlet.ThrowTerminatingError($record)
        }

        $tempPath = [System.IO.Path]::Combine(
            [System.IO.Path]::GetTempPath(),
            ('intunedrop-winzip-{0}.payload' -f [Guid]::NewGuid().ToString('N'))
        )
        $inStream = $encryptedEntry.Open()
        try {
            $outStream = [System.IO.File]::Create($tempPath)
            try {
                $inStream.CopyTo($outStream)
            }
            finally {
                $outStream.Dispose()
            }
        }
        finally {
            $inStream.Dispose()
        }

        $written = (Get-Item -LiteralPath $tempPath).Length
        if ($written -ne $encryptedEntry.Length) {
            Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue
            $record = New-IntuneDropGraphErrorRecord -Message "Extracted encrypted payload length ($written) does not match ZIP entry length ($($encryptedEntry.Length))." -TargetObject $resolved
            $PSCmdlet.ThrowTerminatingError($record)
        }

        return [string]$tempPath
    }
    finally {
        $zip.Dispose()
    }
}

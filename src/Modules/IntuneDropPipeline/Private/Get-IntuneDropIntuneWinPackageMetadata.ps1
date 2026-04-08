<#
.SYNOPSIS
    Reads ApplicationInfo metadata from a Microsoft Win32 Content Prep (.intunewin) file.
.DESCRIPTION
    Supports two layouts from Microsoft IntuneWinAppUtil: (1) current packages — outer ZIP (PK header) containing IntuneWinPackage/Metadata/Detection.xml with ApplicationInfo; (2) legacy packages — 4-byte little-endian XML length followed by UTF-8 ApplicationInfo XML, then encrypted payload. Normalizes encryption fields for Graph commit operations.
.PARAMETER Path
    Full path to the .intunewin file.
#>
function Get-IntuneDropIntuneWinPackageMetadata {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    try {
        $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    }
    catch {
        $record = New-IntuneDropGraphErrorRecord -Message "IntuneWin path could not be resolved: $($_.Exception.Message)" -TargetObject $Path
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $fileInfo = Get-Item -LiteralPath $resolved -ErrorAction Stop
    if ($fileInfo.Length -lt 8) {
        $record = New-IntuneDropGraphErrorRecord -Message "IntuneWin file is too small ($($fileInfo.Length) bytes) to contain a header and XML." -TargetObject $resolved
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $prefixStream = [System.IO.File]::OpenRead($resolved)
    try {
        $lengthPrefix = New-Object byte[] 4
        if ($prefixStream.Read($lengthPrefix, 0, 4) -ne 4) {
            $record = New-IntuneDropGraphErrorRecord -Message 'Could not read first 4 bytes of IntuneWin file.' -TargetObject $resolved
            $PSCmdlet.ThrowTerminatingError($record)
        }
    }
    finally {
        $prefixStream.Dispose()
    }

    $isZipOuter = ($lengthPrefix[0] -eq 0x50 -and $lengthPrefix[1] -eq 0x4B -and $lengthPrefix[2] -eq 0x03 -and $lengthPrefix[3] -eq 0x04)

    $xmlText = $null
    try {
        if ($isZipOuter) {
            $zip = [System.IO.Compression.ZipFile]::OpenRead($resolved)
            try {
                $detectionEntry = $null
                foreach ($entry in $zip.Entries) {
                    $normalized = $entry.FullName -replace '\\', '/'
                    if ($normalized -match '(?i)^IntuneWinPackage/Metadata/Detection\.xml$') {
                        $detectionEntry = $entry
                        break
                    }
                }
                if ($null -eq $detectionEntry) {
                    foreach ($entry in $zip.Entries) {
                        $normalized = $entry.FullName -replace '\\', '/'
                        if ($normalized -match '(?i)/Metadata/Detection\.xml$') {
                            $detectionEntry = $entry
                            break
                        }
                    }
                }
                if ($null -eq $detectionEntry) {
                    $entryNames = @($zip.Entries | ForEach-Object { $_.FullName } | Sort-Object)
                    $sample = ($entryNames | Select-Object -First 12) -join '; '
                    if ($entryNames.Count -gt 12) {
                        $sample += '; ...'
                    }
                    $record = New-IntuneDropGraphErrorRecord -Message (
                        "ZIP-style .intunewin has no Metadata/Detection.xml (expected IntuneWinPackage/Metadata/Detection.xml). Sample entries: $sample"
                    ) -TargetObject $resolved
                    $PSCmdlet.ThrowTerminatingError($record)
                }

                $entryStream = $detectionEntry.Open()
                try {
                    $sr = [System.IO.StreamReader]::new($entryStream, [System.Text.UTF8Encoding]::new($false))
                    $xmlText = $sr.ReadToEnd()
                }
                finally {
                    $sr.Dispose()
                }
            }
            finally {
                $zip.Dispose()
            }
        }
        else {
            $xmlByteLength = [System.BitConverter]::ToInt32($lengthPrefix, 0)
            $maxPayloadAfterPrefix = $fileInfo.Length - 4
            if ($xmlByteLength -gt $maxPayloadAfterPrefix) {
                $record = New-IntuneDropGraphErrorRecord -Message (
                    "Declared XML length ($xmlByteLength bytes) exceeds remaining file size ($maxPayloadAfterPrefix bytes). The file is corrupt or not a legacy Win32 Content Prep .intunewin."
                ) -TargetObject $resolved
                $PSCmdlet.ThrowTerminatingError($record)
            }

            if ($xmlByteLength -lt 8 -or $xmlByteLength -gt (4 * 1024 * 1024)) {
                $record = New-IntuneDropGraphErrorRecord -Message (
                    "IntuneWin XML length $xmlByteLength is out of the expected range (8 bytes to 4 MB). If the file is a current-format ZIP .intunewin, it should start with PK; re-run IntuneWinAppUtil if this file is corrupt."
                ) -TargetObject $resolved
                $PSCmdlet.ThrowTerminatingError($record)
            }

            $fileStream = [System.IO.File]::OpenRead($resolved)
            try {
                $reader = [System.IO.BinaryReader]::new($fileStream)
                $null = $reader.ReadInt32()
                $xmlBytes = $reader.ReadBytes($xmlByteLength)
                if ($xmlBytes.Length -ne $xmlByteLength) {
                    $record = New-IntuneDropGraphErrorRecord -Message 'IntuneWin file ended before XML payload completed.' -TargetObject $resolved
                    $PSCmdlet.ThrowTerminatingError($record)
                }
                $xmlText = [System.Text.Encoding]::UTF8.GetString($xmlBytes)
            }
            finally {
                $fileStream.Dispose()
            }
        }

        [xml]$document = $xmlText
    }
    catch {
        $record = New-IntuneDropGraphErrorRecord -Message "Failed to read IntuneWin metadata: $($_.Exception.Message)" -TargetObject $resolved
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $applicationNode = $document.SelectSingleNode('//*[local-name()="ApplicationInfo"]')
    if ($null -eq $applicationNode) {
        $record = New-IntuneDropGraphErrorRecord -Message 'IntuneWin XML is missing the ApplicationInfo element.' -TargetObject $resolved
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $encryptionNode = $applicationNode.SelectSingleNode('*[local-name()="EncryptionInfo"]')
    if ($null -eq $encryptionNode) {
        $record = New-IntuneDropGraphErrorRecord -Message 'IntuneWin XML is missing EncryptionInfo.' -TargetObject $resolved
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $encryptionMap = [ordered]@{}
    foreach ($child in $encryptionNode.ChildNodes) {
        if ($child.NodeType -ne [System.Xml.XmlNodeType]::Element) {
            continue
        }
        $encryptionMap[$child.LocalName] = $child.InnerText
    }

    $unencryptedSize = $null
    $unencryptedNode = $applicationNode.SelectSingleNode('*[local-name()="UnencryptedContentSize"]')
    if ($null -ne $unencryptedNode -and -not [string]::IsNullOrWhiteSpace($unencryptedNode.InnerText)) {
        $unencryptedSize = [long]$unencryptedNode.InnerText.Trim()
    }

    $setupFileNode = $applicationNode.SelectSingleNode('*[local-name()="SetupFile"]')
    $nameNode = $applicationNode.SelectSingleNode('*[local-name()="Name"]')
    $setupName = $null
    if ($null -ne $setupFileNode -and -not [string]::IsNullOrWhiteSpace($setupFileNode.InnerText)) {
        $setupName = $setupFileNode.InnerText.Trim()
    }
    elseif ($null -ne $nameNode -and -not [string]::IsNullOrWhiteSpace($nameNode.InnerText)) {
        $setupName = $nameNode.InnerText.Trim()
    }
    if ([string]::IsNullOrWhiteSpace($setupName)) {
        $record = New-IntuneDropGraphErrorRecord -Message 'IntuneWin XML is missing SetupFile and Name (setup file name).' -TargetObject $resolved
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $graphEncryption = [ordered]@{
        encryptionKey           = [string]$encryptionMap['EncryptionKey']
        macKey                  = [string]$encryptionMap['MacKey']
        initializationVector    = [string]$encryptionMap['InitializationVector']
        mac                     = [string]$encryptionMap['Mac']
        profileIdentifier       = [string]$encryptionMap['ProfileIdentifier']
        fileDigest              = [string]$encryptionMap['FileDigest']
        fileDigestAlgorithm     = [string]$encryptionMap['FileDigestAlgorithm']
    }

    foreach ($key in @('encryptionKey', 'macKey', 'initializationVector', 'mac', 'profileIdentifier', 'fileDigest')) {
        if ([string]::IsNullOrWhiteSpace($graphEncryption[$key])) {
            $record = New-IntuneDropGraphErrorRecord -Message "Encryption metadata is missing required field '$key'." -TargetObject $resolved
            $PSCmdlet.ThrowTerminatingError($record)
        }
    }
    if ([string]::IsNullOrWhiteSpace($graphEncryption['fileDigestAlgorithm'])) {
        $graphEncryption['fileDigestAlgorithm'] = 'SHA256'
    }

    [pscustomobject]@{
        SetupFileName          = $setupName
        UnencryptedContentSize = $unencryptedSize
        FileEncryptionInfo     = [pscustomobject]$graphEncryption
        RawXml                 = $xmlText
        EncryptedFileBytes     = $fileInfo.Length
        IntuneWinPath          = $resolved
    }
}

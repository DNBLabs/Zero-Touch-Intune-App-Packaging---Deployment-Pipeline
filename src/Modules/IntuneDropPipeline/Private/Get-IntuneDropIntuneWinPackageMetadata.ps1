<#
.SYNOPSIS
    Reads the UTF-8 XML header from a Microsoft Win32 Content Prep (.intunewin) file.
.DESCRIPTION
    The prep tool prepends a 4-byte little-endian length followed by ApplicationInfo XML describing encryption and the enclosed setup file name. This command parses that XML and normalizes encryption fields for Graph commit operations.
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
    $fileStream = [System.IO.File]::OpenRead($resolved)
    try {
        $reader = [System.IO.BinaryReader]::new($fileStream)
        $xmlByteLength = $reader.ReadInt32()
        if ($xmlByteLength -lt 8 -or $xmlByteLength -gt (4 * 1024 * 1024)) {
            $record = New-IntuneDropGraphErrorRecord -Message "IntuneWin XML length $xmlByteLength is out of the expected range." -TargetObject $resolved
            $PSCmdlet.ThrowTerminatingError($record)
        }

        $xmlBytes = $reader.ReadBytes($xmlByteLength)
        if ($xmlBytes.Length -ne $xmlByteLength) {
            $record = New-IntuneDropGraphErrorRecord -Message 'IntuneWin file ended before XML payload completed.' -TargetObject $resolved
            $PSCmdlet.ThrowTerminatingError($record)
        }

        $xmlText = [System.Text.Encoding]::UTF8.GetString($xmlBytes)
        [xml]$document = $xmlText
    }
    catch {
        $record = New-IntuneDropGraphErrorRecord -Message "Failed to read IntuneWin metadata: $($_.Exception.Message)" -TargetObject $resolved
        $PSCmdlet.ThrowTerminatingError($record)
    }
    finally {
        $fileStream.Dispose()
    }

    $applicationNode = $document.ApplicationInfo
    if ($null -eq $applicationNode) {
        $record = New-IntuneDropGraphErrorRecord -Message 'IntuneWin XML is missing the ApplicationInfo element.' -TargetObject $resolved
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $encryptionNode = $applicationNode.EncryptionInfo
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
    if ($null -ne $applicationNode.UnencryptedContentSize -and -not [string]::IsNullOrWhiteSpace([string]$applicationNode.UnencryptedContentSize)) {
        $unencryptedSize = [long]$applicationNode.UnencryptedContentSize
    }

    $setupName = [string]$applicationNode.Name
    if ([string]::IsNullOrWhiteSpace($setupName)) {
        $record = New-IntuneDropGraphErrorRecord -Message 'IntuneWin XML is missing ApplicationInfo Name (setup file name).' -TargetObject $resolved
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

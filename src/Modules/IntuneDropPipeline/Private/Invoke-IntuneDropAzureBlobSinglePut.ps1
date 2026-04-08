<#
.SYNOPSIS
    Uploads a local file to Azure Blob Storage using a SAS URL returned by Intune.
.DESCRIPTION
    Stages the file with Azure Block Blob Put Block requests and completes via Put Block List, matching Microsoft Intune Win32 LOB samples (powershell-intune-samples / IntuneWin32App). A single Put Blob can return success yet Intune commit may still report commitFileFailed. Chunks use HttpClient ByteArrayContent (raw bytes, no text encoding). Chunk size is 6 MiB per the official samples.
.PARAMETER SasUri
    Full Azure Blob SAS URI from mobileAppContentFile.azureStorageUri.
.PARAMETER FilePath
    Path to the file whose bytes Intune will verify on commit (full .intunewin or extracted inner payload).
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
        $resolvedPath = (Resolve-Path -LiteralPath $FilePath -ErrorAction Stop).Path
        $fileItem = Get-Item -LiteralPath $resolvedPath
        $fileSize = [long]$fileItem.Length
        if ($fileSize -lt 1) {
            $record = New-IntuneDropGraphErrorRecord -Message 'Azure blob upload requires a non-empty file.' -TargetObject $resolvedPath
            $PSCmdlet.ThrowTerminatingError($record)
        }

        $chunkSizeInBytes = 6L * 1024L * 1024L
        $chunkCount = [int][System.Math]::Ceiling($fileSize / [double]$chunkSizeInBytes)
        if ($chunkCount -gt 9999) {
            $record = New-IntuneDropGraphErrorRecord -Message "File size requires more than 9999 upload chunks ($chunkCount); not supported." -TargetObject $resolvedPath
            $PSCmdlet.ThrowTerminatingError($record)
        }

        $sasTrim = $SasUri.Trim()
        $queryJoiner = if ($sasTrim -match '\?') { '&' } else { '?' }

        $httpClient = [System.Net.Http.HttpClient]::new()
        try {
            $reader = [System.IO.BinaryReader]::new([System.IO.File]::OpenRead($resolvedPath))
            try {
                $blockIds = [System.Collections.Generic.List[string]]::new()
                for ($chunk = 0; $chunk -lt $chunkCount; $chunk++) {
                    $blockIdPlain = $chunk.ToString('0000')
                    $blockId = [string][System.Convert]::ToBase64String(
                        [System.Text.Encoding]::ASCII.GetBytes($blockIdPlain))
                    $blockIds.Add($blockId)

                    $start = [long]$chunk * $chunkSizeInBytes
                    $length = [long][System.Math]::Min($chunkSizeInBytes, $fileSize - $start)
                    $bytes = $reader.ReadBytes([int]$length)
                    if ($bytes.Length -ne [int]$length) {
                        throw "Read $([int]$length) bytes for chunk $chunk but got $($bytes.Length)."
                    }

                    $encodedBlockId = [Uri]::EscapeDataString($blockId)
                    $putBlockAbsolute = "${sasTrim}${queryJoiner}comp=block&blockid=${encodedBlockId}"
                    $putBlockUri = [Uri]::new($putBlockAbsolute)

                    $chunkContent = [System.Net.Http.ByteArrayContent]::new($bytes)
                    $chunkContent.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/octet-stream')

                    $putRequest = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Put, $putBlockUri)
                    $null = $putRequest.Headers.TryAddWithoutValidation('x-ms-blob-type', 'BlockBlob')
                    $putRequest.Content = $chunkContent

                    $putResponse = $httpClient.SendAsync($putRequest).GetAwaiter().GetResult()
                    try {
                        if (-not $putResponse.IsSuccessStatusCode) {
                            $errorText = $putResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                            $cap = [Math]::Min(800, $errorText.Length)
                            $snippet = if ($cap -gt 0) { $errorText.Substring(0, $cap) } else { [string]::Empty }
                            throw ("Azure Put Block returned HTTP {0}. {1}" -f [int]$putResponse.StatusCode, $snippet)
                        }
                    }
                    finally {
                        $putResponse.Dispose()
                        $putRequest.Dispose()
                    }
                }
            }
            finally {
                $reader.Dispose()
            }

            $listBuilder = [System.Text.StringBuilder]::new()
            [void]$listBuilder.Append('<?xml version="1.0" encoding="utf-8"?><BlockList>')
            foreach ($bid in $blockIds) {
                [void]$listBuilder.Append('<Latest>').Append($bid).Append('</Latest>')
            }
            [void]$listBuilder.Append('</BlockList>')
            $blockListXml = $listBuilder.ToString()

            $listAbsolute = "${sasTrim}${queryJoiner}comp=blocklist"
            $listUri = [Uri]::new($listAbsolute)
            $listContent = [System.Net.Http.StringContent]::new(
                $blockListXml,
                [System.Text.Encoding]::UTF8,
                'application/xml')

            $listRequest = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Put, $listUri)
            $listRequest.Content = $listContent

            $listResponse = $httpClient.SendAsync($listRequest).GetAwaiter().GetResult()
            try {
                if (-not $listResponse.IsSuccessStatusCode) {
                    $errorText = $listResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                    $cap = [Math]::Min(800, $errorText.Length)
                    $snippet = if ($cap -gt 0) { $errorText.Substring(0, $cap) } else { [string]::Empty }
                    throw ("Azure Put Block List returned HTTP {0}. {1}" -f [int]$listResponse.StatusCode, $snippet)
                }
            }
            finally {
                $listResponse.Dispose()
                $listRequest.Dispose()
            }
        }
        finally {
            $httpClient.Dispose()
        }
    }
    catch {
        $record = New-IntuneDropGraphErrorRecord -Message "Azure blob upload failed: $($_.Exception.Message)" -TargetObject $SasUri
        $PSCmdlet.ThrowTerminatingError($record)
    }
}

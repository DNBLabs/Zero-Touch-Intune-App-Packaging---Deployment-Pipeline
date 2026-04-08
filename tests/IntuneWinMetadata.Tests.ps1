<#
.SYNOPSIS
    Tests private IntuneWin header parsing via InModuleScope.
#>
BeforeAll {
    $repoRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $moduleManifest = Join-Path -Path $repoRoot -ChildPath 'src\Modules\IntuneDropPipeline\IntuneDropPipeline.psd1'
    Import-Module -Name $moduleManifest -Force

    function script:New-IntuneDropTestIntuneWinFile {
        param([Parameter(Mandatory)][string] $Path)

        $xml = @'
<ApplicationInfo>
  <Name>InsideSetup.msi</Name>
  <UnencryptedContentSize>2048</UnencryptedContentSize>
  <EncryptionInfo>
    <EncryptionKey>ZW5j</EncryptionKey>
    <MacKey>bWFj</MacKey>
    <InitializationVector>aXY=</InitializationVector>
    <Mac>a2V5</Mac>
    <ProfileIdentifier>cHJm</ProfileIdentifier>
    <FileDigest>ZGln</FileDigest>
    <FileDigestAlgorithm>SHA256</FileDigestAlgorithm>
  </EncryptionInfo>
</ApplicationInfo>
'@
        $utf8 = [System.Text.Encoding]::UTF8.GetBytes($xml)
        $stream = [System.IO.File]::Create($Path)
        try {
            $lengthBytes = [System.BitConverter]::GetBytes([int]$utf8.Length)
            $stream.Write($lengthBytes, 0, 4)
            $stream.Write($utf8, 0, $utf8.Length)
            $padding = New-Object byte[] 32
            $stream.Write($padding, 0, $padding.Length)
        }
        finally {
            $stream.Dispose()
        }
    }

    function script:New-IntuneDropTestZipIntuneWinFile {
        param([Parameter(Mandatory)][string] $Path)

        $xml = @'
<ApplicationInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" ToolVersion="1.8.4.0">
  <Name>BundleName</Name>
  <SetupFile>InsideSetup.msi</SetupFile>
  <UnencryptedContentSize>4096</UnencryptedContentSize>
  <EncryptionInfo>
    <EncryptionKey>ZW5j</EncryptionKey>
    <MacKey>bWFj</MacKey>
    <InitializationVector>aXY=</InitializationVector>
    <Mac>a2V5</Mac>
    <ProfileIdentifier>cHJm</ProfileIdentifier>
    <FileDigest>ZGln</FileDigest>
    <FileDigestAlgorithm>SHA256</FileDigestAlgorithm>
  </EncryptionInfo>
</ApplicationInfo>
'@
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Force
        }
        $zip = [System.IO.Compression.ZipFile]::Open($Path, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $entry = $zip.CreateEntry('IntuneWinPackage/Metadata/Detection.xml')
            $sw = [System.IO.StreamWriter]::new($entry.Open())
            try {
                $sw.Write($xml)
            }
            finally {
                $sw.Dispose()
            }
        }
        finally {
            $zip.Dispose()
        }
    }
}

AfterAll {
    Remove-Module -Name IntuneDropPipeline -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IntuneDropIntuneWinPackageMetadata' {
    It 'extracts metadata from current-format ZIP .intunewin (Detection.xml inside the archive)' {
        $zipIntuneWin = Join-Path -Path $TestDrive -ChildPath 'zip-format.intunewin'
        New-IntuneDropTestZipIntuneWinFile -Path $zipIntuneWin

        InModuleScope -ModuleName 'IntuneDropPipeline' -ArgumentList @($zipIntuneWin) -ScriptBlock {
            param([string] $IntuneWinPath)
            $metadata = Get-IntuneDropIntuneWinPackageMetadata -Path $IntuneWinPath
            $metadata.SetupFileName | Should -Be 'InsideSetup.msi'
            $metadata.UnencryptedContentSize | Should -Be 4096
            $metadata.FileEncryptionInfo.encryptionKey | Should -Be 'ZW5j'
            $metadata.EncryptedContentSize | Should -Be $null
            $metadata.PackageLayout | Should -Be 'Zip'
        }
    }

    It 'ZIP .intunewin sets EncryptedContentSize from IntuneWinPackage/Contents/IntunePackage.intunewin entry length' {
        $zipIntuneWin = Join-Path -Path $TestDrive -ChildPath 'zip-with-inner.intunewin'
        if (Test-Path -LiteralPath $zipIntuneWin) {
            Remove-Item -LiteralPath $zipIntuneWin -Force
        }
        $innerPayload = [byte[]]::new(123)
        for ($i = 0; $i -lt $innerPayload.Length; $i++) { $innerPayload[$i] = [byte]($i % 251) }

        $xml = @'
<ApplicationInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema" ToolVersion="1.8.4.0">
  <Name>BundleName</Name>
  <SetupFile>InsideSetup.msi</SetupFile>
  <UnencryptedContentSize>4096</UnencryptedContentSize>
  <EncryptionInfo>
    <EncryptionKey>ZW5j</EncryptionKey>
    <MacKey>bWFj</MacKey>
    <InitializationVector>aXY=</InitializationVector>
    <Mac>a2V5</Mac>
    <ProfileIdentifier>cHJm</ProfileIdentifier>
    <FileDigest>ZGln</FileDigest>
    <FileDigestAlgorithm>SHA256</FileDigestAlgorithm>
  </EncryptionInfo>
</ApplicationInfo>
'@
        $zip = [System.IO.Compression.ZipFile]::Open($zipIntuneWin, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $e1 = $zip.CreateEntry('IntuneWinPackage/Metadata/Detection.xml')
            $sw1 = [System.IO.StreamWriter]::new($e1.Open())
            try { $sw1.Write($xml) }
            finally { $sw1.Dispose() }

            $e2 = $zip.CreateEntry('IntuneWinPackage/Contents/IntunePackage.intunewin')
            $zs = $e2.Open()
            try { $zs.Write($innerPayload, 0, $innerPayload.Length) }
            finally { $zs.Dispose() }
        }
        finally {
            $zip.Dispose()
        }

        InModuleScope -ModuleName 'IntuneDropPipeline' -ArgumentList @($zipIntuneWin) -ScriptBlock {
            param([string] $IntuneWinPath)
            $metadata = Get-IntuneDropIntuneWinPackageMetadata -Path $IntuneWinPath
            $metadata.EncryptedContentSize | Should -Be 123
            $metadata.PackageLayout | Should -Be 'Zip'

            $extracted = Export-IntuneDropIntuneWinZipEncryptedPayloadToTemp -SourcePath $IntuneWinPath
            try {
                (Get-Item -LiteralPath $extracted).Length | Should -Be 123
            }
            finally {
                Remove-Item -LiteralPath $extracted -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'throws when ZIP .intunewin has no Detection.xml entry' {
        $badZip = Join-Path -Path $TestDrive -ChildPath 'empty-package.intunewin'
        if (Test-Path -LiteralPath $badZip) {
            Remove-Item -LiteralPath $badZip -Force
        }
        $zip = [System.IO.Compression.ZipFile]::Open($badZip, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $entry = $zip.CreateEntry('other/readme.txt')
            $sw = [System.IO.StreamWriter]::new($entry.Open())
            $sw.Write('nope')
            $sw.Dispose()
        }
        finally {
            $zip.Dispose()
        }

        $err = {
            InModuleScope -ModuleName 'IntuneDropPipeline' -ScriptBlock {
                param([string] $Path)
                Get-IntuneDropIntuneWinPackageMetadata -Path $Path
            } -ArgumentList $badZip
        } | Should -Throw -PassThru

        $err.Exception.Message | Should -Match 'ERR_GRAPH:'
        $err.Exception.Message | Should -Match 'Detection\.xml'
    }

    It 'extracts setup name and encryption fields from a synthetic intunewin file' {
        $testFile = Join-Path -Path $TestDrive -ChildPath 'sample.intunewin'
        New-IntuneDropTestIntuneWinFile -Path $testFile

        InModuleScope -ModuleName 'IntuneDropPipeline' -ArgumentList @($testFile) -ScriptBlock {
            param([string] $IntuneWinPath)
            $metadata = Get-IntuneDropIntuneWinPackageMetadata -Path $IntuneWinPath
            $metadata.SetupFileName | Should -Be 'InsideSetup.msi'
            $metadata.UnencryptedContentSize | Should -Be 2048
            $metadata.FileEncryptionInfo.encryptionKey | Should -Be 'ZW5j'
            $metadata.FileEncryptionInfo.fileDigestAlgorithm | Should -Be 'SHA256'
            $metadata.EncryptedContentSize | Should -Be 32
            $metadata.PackageLayout | Should -Be 'Legacy'
        }
    }
}

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
}

AfterAll {
    Remove-Module -Name IntuneDropPipeline -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IntuneDropIntuneWinPackageMetadata' {
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
        }
    }
}

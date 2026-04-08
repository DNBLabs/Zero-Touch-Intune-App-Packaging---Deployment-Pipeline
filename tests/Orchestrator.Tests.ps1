<#
.SYNOPSIS
    Tests for Invoke-IntuneDropForFile end-to-end wiring with mocked packaging and Graph steps.
#>
BeforeAll {
    $script:repoRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $script:moduleManifest = Join-Path -Path $script:repoRoot -ChildPath 'src\Modules\IntuneDropPipeline\IntuneDropPipeline.psd1'

    function script:New-IntuneDropOrchestratorTestIntuneWinStub {
        param([Parameter(Mandatory)][string] $Path)
        $xml = @'
<ApplicationInfo>
  <Name>Stub.exe</Name>
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
            $stream.Write([System.BitConverter]::GetBytes([int]$utf8.Length), 0, 4)
            $stream.Write($utf8, 0, $utf8.Length)
            $stream.Write((New-Object byte[] 16), 0, 16)
        }
        finally {
            $stream.Dispose()
        }
    }
}

AfterAll {
    Remove-Module -Name IntuneDropPipeline -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-IntuneDropForFile' {
    BeforeEach {
        $script:savedEnv = @{}
        foreach ($key in @(
                'INTUNE_DROP_INBOX_PATH',
                'INTUNE_DROP_DONE_PATH',
                'INTUNE_DROP_FAILED_PATH',
                'INTUNE_DROP_STAGING_PATH',
                'INTUNE_DROP_PREP_TOOL_EXE',
                'INTUNE_DROP_TEST_GROUP_ID',
                'AZURE_TENANT_ID',
                'AZURE_CLIENT_ID',
                'AZURE_CLIENT_SECRET'
            )) {
            $script:savedEnv[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
        }
    }

    AfterEach {
        foreach ($entry in $script:savedEnv.GetEnumerator()) {
            if ($null -eq $entry.Value -or $entry.Value -eq '') {
                Remove-Item -Path "Env:$($entry.Key)" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item -Path "Env:$($entry.Key)" -Value $entry.Value
            }
        }
        Remove-Module -Name IntuneDropPipeline -Force -ErrorAction SilentlyContinue
    }

    It 'moves installer to done when packaging and Graph steps succeed' {
        $inbox = Join-Path -Path $TestDrive -ChildPath 'inbox'
        $done = Join-Path -Path $TestDrive -ChildPath 'done'
        $failed = Join-Path -Path $TestDrive -ChildPath 'failed'
        $staging = Join-Path -Path $TestDrive -ChildPath 'staging'
        $null = New-Item -ItemType Directory -Path @($inbox, $done, $failed, $staging) -Force

        $env:INTUNE_DROP_INBOX_PATH = $inbox
        $env:INTUNE_DROP_DONE_PATH = $done
        $env:INTUNE_DROP_FAILED_PATH = $failed
        $env:INTUNE_DROP_STAGING_PATH = $staging
        $env:INTUNE_DROP_PREP_TOOL_EXE = 'C:\Tools\IntuneWinAppUtil.exe'
        $env:INTUNE_DROP_TEST_GROUP_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $env:AZURE_TENANT_ID = '11111111-1111-1111-1111-111111111111'
        $env:AZURE_CLIENT_ID = '22222222-2222-2222-2222-222222222222'
        $env:AZURE_CLIENT_SECRET = 'unit-test-secret'

        $installerPath = Join-Path -Path $inbox -ChildPath 'Fabrikam_App_1.0.0.exe'
        $null = New-Item -Path $installerPath -ItemType File -Value '' -Force

        $stubIntuneWin = Join-Path -Path $TestDrive -ChildPath 'stub.intunewin'
        New-IntuneDropOrchestratorTestIntuneWinStub -Path $stubIntuneWin

        Import-Module -Name $script:moduleManifest -Force

        Mock -ModuleName IntuneDropPipeline -CommandName New-IntuneDropWin32Package -MockWith {
            return @{ IntuneWinPath = $stubIntuneWin }
        }

        Mock -ModuleName IntuneDropPipeline -CommandName Get-IntuneDropMgContext -MockWith { return $null }

        Mock -ModuleName IntuneDropPipeline -CommandName Connect-IntuneDropGraphSession -MockWith { }

        Mock -ModuleName IntuneDropPipeline -CommandName New-IntuneDropWin32LobApp -MockWith {
            return @{ Id = '33333333-3333-3333-3333-333333333333' }
        }

        Mock -ModuleName IntuneDropPipeline -CommandName Publish-IntuneDropWin32LobIntuneWinContent -MockWith { }

        Mock -ModuleName IntuneDropPipeline -CommandName New-IntuneDropWin32LobGroupAssignment -MockWith { }

        Invoke-IntuneDropForFile -LiteralPath $installerPath

        $moved = Join-Path -Path $done -ChildPath 'Fabrikam_App_1.0.0.exe'
        Test-Path -LiteralPath $moved -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $installerPath | Should -BeFalse
    }

    It 'moves installer to failed with reason sidecar when filename does not parse' {
        $inbox = Join-Path -Path $TestDrive -ChildPath 'inbox2'
        $done = Join-Path -Path $TestDrive -ChildPath 'done2'
        $failed = Join-Path -Path $TestDrive -ChildPath 'failed2'
        $staging = Join-Path -Path $TestDrive -ChildPath 'staging2'
        $null = New-Item -ItemType Directory -Path @($inbox, $done, $failed, $staging) -Force

        $env:INTUNE_DROP_INBOX_PATH = $inbox
        $env:INTUNE_DROP_DONE_PATH = $done
        $env:INTUNE_DROP_FAILED_PATH = $failed
        $env:INTUNE_DROP_STAGING_PATH = $staging
        $env:INTUNE_DROP_PREP_TOOL_EXE = 'C:\Tools\IntuneWinAppUtil.exe'
        $env:INTUNE_DROP_TEST_GROUP_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $env:AZURE_TENANT_ID = '11111111-1111-1111-1111-111111111111'
        $env:AZURE_CLIENT_ID = '22222222-2222-2222-2222-222222222222'
        $env:AZURE_CLIENT_SECRET = 'unit-test-secret'

        $installerPath = Join-Path -Path $inbox -ChildPath 'setup.exe'
        $null = New-Item -Path $installerPath -ItemType File -Value '' -Force

        Import-Module -Name $script:moduleManifest -Force

        { Invoke-IntuneDropForFile -LiteralPath $installerPath } | Should -Throw

        $failedLeaf = Join-Path -Path $failed -ChildPath 'setup.exe'
        Test-Path -LiteralPath $failedLeaf -PathType Leaf | Should -BeTrue
        $reasonPath = "$failedLeaf.reason.txt"
        Test-Path -LiteralPath $reasonPath | Should -BeTrue
        (Get-Content -LiteralPath $reasonPath -Raw) | Should -Match 'Vendor_AppName'
    }
}

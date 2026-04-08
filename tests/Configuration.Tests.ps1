<#
.SYNOPSIS
    Pester tests for IntuneDropPipeline configuration resolution and required environment validation.
#>
BeforeAll {
    $repoRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $moduleManifest = Join-Path -Path $repoRoot -ChildPath 'src\Modules\IntuneDropPipeline\IntuneDropPipeline.psd1'

    $script:expectedInbox = [System.IO.Path]::GetFullPath((Join-Path -Path $repoRoot -ChildPath 'inbox'))
}

Describe 'IntuneDropPipeline configuration' {
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
                'AZURE_CLIENT_SECRET',
                'AZURE_CLIENT_CERTIFICATE_THUMBPRINT',
                'AZURE_CLIENT_CERTIFICATE_PATH',
                'AZURE_CLIENT_CERTIFICATE_PASSWORD'
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

    It 'imports the module from the manifest' {
        { Import-Module -Name $moduleManifest -Force -ErrorAction Stop } | Should -Not -Throw
        Get-Module -Name IntuneDropPipeline | Should -Not -BeNullOrEmpty
    }

    It 'resolves default inbox path relative to the repository root' {
        $env:INTUNE_DROP_PREP_TOOL_EXE = 'C:\Tools\IntuneWinAppUtil.exe'
        $env:INTUNE_DROP_TEST_GROUP_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $env:AZURE_TENANT_ID = '11111111-1111-1111-1111-111111111111'
        $env:AZURE_CLIENT_ID = '22222222-2222-2222-2222-222222222222'
        Remove-Item Env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT -ErrorAction SilentlyContinue
        Remove-Item Env:AZURE_CLIENT_CERTIFICATE_PATH -ErrorAction SilentlyContinue
        $env:AZURE_CLIENT_SECRET = 'unit-test-secret'

        Import-Module -Name $moduleManifest -Force

        $configuration = Get-IntuneDropConfiguration
        $configuration.InboxPath | Should -Be $expectedInbox
        $configuration.PrepToolExe | Should -Be 'C:\Tools\IntuneWinAppUtil.exe'
        $configuration.AzureClientCertificateThumbprint | Should -BeNullOrEmpty
        $configuration.AzureClientSecret | Should -Be 'unit-test-secret'
    }

    It 'accepts certificate thumbprint without client secret' {
        $env:INTUNE_DROP_PREP_TOOL_EXE = 'C:\Tools\IntuneWinAppUtil.exe'
        $env:INTUNE_DROP_TEST_GROUP_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $env:AZURE_TENANT_ID = '11111111-1111-1111-1111-111111111111'
        $env:AZURE_CLIENT_ID = '22222222-2222-2222-2222-222222222222'
        Remove-Item Env:AZURE_CLIENT_SECRET -ErrorAction SilentlyContinue
        Remove-Item Env:AZURE_CLIENT_CERTIFICATE_PATH -ErrorAction SilentlyContinue
        $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT = 'ABCDEF0123456789FEDCBA9876543210ABCDEF01'

        Import-Module -Name $moduleManifest -Force

        $configuration = Get-IntuneDropConfiguration
        $configuration.AzureClientCertificateThumbprint | Should -Be 'ABCDEF0123456789FEDCBA9876543210ABCDEF01'
        $configuration.AzureClientSecret | Should -BeNullOrEmpty
    }

    It 'throws when no graph application credential is configured' {
        $env:INTUNE_DROP_PREP_TOOL_EXE = 'C:\Tools\IntuneWinAppUtil.exe'
        $env:INTUNE_DROP_TEST_GROUP_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $env:AZURE_TENANT_ID = '11111111-1111-1111-1111-111111111111'
        $env:AZURE_CLIENT_ID = '22222222-2222-2222-2222-222222222222'
        Remove-Item Env:AZURE_CLIENT_SECRET -ErrorAction SilentlyContinue
        Remove-Item Env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT -ErrorAction SilentlyContinue
        Remove-Item Env:AZURE_CLIENT_CERTIFICATE_PATH -ErrorAction SilentlyContinue

        Import-Module -Name $moduleManifest -Force

        $exception = { Get-IntuneDropConfiguration } | Should -Throw -PassThru
        $exception.Exception.Message | Should -Match 'Missing Graph application credential'
    }

    It 'throws when more than one graph credential is configured' {
        $env:INTUNE_DROP_PREP_TOOL_EXE = 'C:\Tools\IntuneWinAppUtil.exe'
        $env:INTUNE_DROP_TEST_GROUP_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $env:AZURE_TENANT_ID = '11111111-1111-1111-1111-111111111111'
        $env:AZURE_CLIENT_ID = '22222222-2222-2222-2222-222222222222'
        $env:AZURE_CLIENT_SECRET = 'unit-test-secret'
        $env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT = 'ABCDEF0123456789FEDCBA9876543210ABCDEF01'
        Remove-Item Env:AZURE_CLIENT_CERTIFICATE_PATH -ErrorAction SilentlyContinue

        Import-Module -Name $moduleManifest -Force

        $exception = { Get-IntuneDropConfiguration } | Should -Throw -PassThru
        $exception.Exception.Message | Should -Match 'Ambiguous Graph application credential'
    }

    It 'lists all missing required keys when several base keys are absent' {
        Remove-Item Env:INTUNE_DROP_PREP_TOOL_EXE -ErrorAction SilentlyContinue
        Remove-Item Env:AZURE_CLIENT_ID -ErrorAction SilentlyContinue
        $env:INTUNE_DROP_TEST_GROUP_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $env:AZURE_TENANT_ID = '11111111-1111-1111-1111-111111111111'
        Remove-Item Env:AZURE_CLIENT_CERTIFICATE_THUMBPRINT -ErrorAction SilentlyContinue
        Remove-Item Env:AZURE_CLIENT_CERTIFICATE_PATH -ErrorAction SilentlyContinue
        $env:AZURE_CLIENT_SECRET = 'unit-test-secret'

        Import-Module -Name $moduleManifest -Force

        $exception = { Get-IntuneDropConfiguration } | Should -Throw -PassThru
        $message = $exception.Exception.Message
        $message | Should -Match 'AZURE_CLIENT_ID'
        $message | Should -Match 'INTUNE_DROP_PREP_TOOL_EXE'
        $message | Should -Not -Match 'unit-test-secret'
    }
}

<#
.SYNOPSIS
    Pester tests for Invoke-IntuneDropInboxSweep and Process-Inbox.ps1 parameter contract.
#>
BeforeAll {
    $script:repoRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $script:moduleManifest = Join-Path -Path $script:repoRoot -ChildPath 'src\Modules\IntuneDropPipeline\IntuneDropPipeline.psd1'
    $script:processInboxScript = Join-Path -Path $script:repoRoot -ChildPath 'src\Process-Inbox.ps1'
}

AfterAll {
    Remove-Module -Name IntuneDropPipeline -Force -ErrorAction SilentlyContinue
}

Describe 'Invoke-IntuneDropInboxSweep' {
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

    It 'calls Invoke-IntuneDropForFile once per eligible file and skips empty inbox on second sweep' {
        $inbox = Join-Path -Path $TestDrive -ChildPath 'inbox_pi'
        $done = Join-Path -Path $TestDrive -ChildPath 'done_pi'
        $failed = Join-Path -Path $TestDrive -ChildPath 'failed_pi'
        $staging = Join-Path -Path $TestDrive -ChildPath 'staging_pi'
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

        $null = New-Item -Path (Join-Path $inbox 'A_App_1.0.exe') -ItemType File -Force
        $null = New-Item -Path (Join-Path $inbox 'B_App_2.0.msi') -ItemType File -Force

        Import-Module -Name $script:moduleManifest -Force

        $script:inboxSweepInvokeCount = 0
        Mock -ModuleName IntuneDropPipeline -CommandName Invoke-IntuneDropForFile -MockWith {
            $script:inboxSweepInvokeCount++
        }

        Invoke-IntuneDropInboxSweep
        $script:inboxSweepInvokeCount | Should -Be 2

        Get-ChildItem -LiteralPath $inbox -File | Remove-Item -Force

        Invoke-IntuneDropInboxSweep
        $script:inboxSweepInvokeCount | Should -Be 2
    }
}

Describe 'Process-Inbox.ps1' {
    It 'fails when -Once is not supplied' {
        $caught = { & $script:processInboxScript } | Should -Throw -PassThru
        $caught.Exception.Message | Should -Match 'requires -Once'
    }
}

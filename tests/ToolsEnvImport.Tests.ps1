<#
.SYNOPSIS
    Tests for tools/Import-IntuneDropEnv.ps1 line parsing and env application.
#>
BeforeAll {
    $script:repoRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $script:importEnvScript = Join-Path -Path $script:repoRoot -ChildPath 'tools\Import-IntuneDropEnv.ps1'
}

Describe 'Import-IntuneDropEnv.ps1' {
    AfterEach {
        Remove-Item -Path 'Env:INTUNE_DROP_ENV_TEST_A' -ErrorAction SilentlyContinue
        Remove-Item -Path 'Env:INTUNE_DROP_ENV_TEST_B' -ErrorAction SilentlyContinue
    }

    It 'loads KEY=value lines and skips comments and blanks' {
        $envFile = Join-Path -Path $TestDrive -ChildPath 'sample.env'
        @'
INTUNE_DROP_ENV_TEST_A=alpha

# comment
INTUNE_DROP_ENV_TEST_B=beta tail
'@ | Set-Content -LiteralPath $envFile -Encoding utf8

        & $script:importEnvScript -LiteralPath $envFile

        $env:INTUNE_DROP_ENV_TEST_A | Should -Be 'alpha'
        $env:INTUNE_DROP_ENV_TEST_B | Should -Be 'beta tail'
    }

    It 'throws when the env file is missing' {
        $missing = Join-Path -Path $TestDrive -ChildPath 'nope.env'
        { & $script:importEnvScript -LiteralPath $missing } | Should -Throw
    }
}

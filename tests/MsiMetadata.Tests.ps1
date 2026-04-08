<#
.SYNOPSIS
    Pester tests for Get-IntuneDropMsiProductCode (Windows Installer COM).
#>
BeforeAll {
    $repoRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $moduleManifest = Join-Path -Path $repoRoot -ChildPath 'src\Modules\IntuneDropPipeline\IntuneDropPipeline.psd1'
    Import-Module -Name $moduleManifest -Force
}

AfterAll {
    Remove-Module -Name IntuneDropPipeline -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IntuneDropMsiProductCode' {
    It 'fails on non-Windows with ERR_MSI_METADATA' -Skip:$IsWindows {
        $err = { Get-IntuneDropMsiProductCode -Path '/tmp/dummy.msi' } | Should -Throw -PassThru
        $err.FullyQualifiedErrorId | Should -BeLike 'ERR_MSI_METADATA*'
        $err.Exception.Message | Should -Match 'ERR_MSI_METADATA:'
    }

    It 'throws ERR_MSI_METADATA when the file does not exist' -Skip:(-not $IsWindows) {
        $badPath = Join-Path -Path $TestDrive -ChildPath 'missing.msi'
        $err = { Get-IntuneDropMsiProductCode -Path $badPath } | Should -Throw -PassThru
        $err.FullyQualifiedErrorId | Should -BeLike 'ERR_MSI_METADATA*'
    }

    It 'throws ERR_MSI_METADATA when the path is not an .msi extension' -Skip:(-not $IsWindows) {
        $txt = Join-Path -Path $TestDrive -ChildPath 'x.txt'
        Set-Content -LiteralPath $txt -Value 'noop'
        $err = { Get-IntuneDropMsiProductCode -Path $txt } | Should -Throw -PassThru
        $err.FullyQualifiedErrorId | Should -BeLike 'ERR_MSI_METADATA*'
        $err.Exception.Message | Should -Match '\.msi'
    }

    It 'throws ERR_MSI_METADATA when the file is not a valid MSI database' -Skip:(-not $IsWindows) {
        $msi = Join-Path -Path $TestDrive -ChildPath 'empty.msi'
        Set-Content -LiteralPath $msi -Value 'not an msi' -Encoding utf8
        $err = { Get-IntuneDropMsiProductCode -Path $msi } | Should -Throw -PassThru
        $err.FullyQualifiedErrorId | Should -BeLike 'ERR_MSI_METADATA*'
    }

    It 'accepts upper-case .MSI extension then fails on invalid database' -Skip:(-not $IsWindows) {
        $msi = Join-Path -Path $TestDrive -ChildPath 'X.MSI'
        Set-Content -LiteralPath $msi -Value 'dummy' -Encoding utf8
        $err = { Get-IntuneDropMsiProductCode -Path $msi } | Should -Throw -PassThru
        $err.Exception.Message | Should -Not -Match "extension '\.msi'"
        $err.FullyQualifiedErrorId | Should -BeLike 'ERR_MSI_METADATA*'
    }
}

Describe 'Get-IntuneDropMsiProductCode (integration)' {
    It 'reads ProductCode when INTUNE_DROP_TEST_MSI_PATH points to a real MSI' -Skip:(
        -not $IsWindows -or
        [string]::IsNullOrWhiteSpace($env:INTUNE_DROP_TEST_MSI_PATH) -or
        -not (Test-Path -LiteralPath $env:INTUNE_DROP_TEST_MSI_PATH)
    ) {
        $code = Get-IntuneDropMsiProductCode -Path $env:INTUNE_DROP_TEST_MSI_PATH
        $code | Should -Match '^\{[0-9A-Fa-f-]{36}\}$'
    }
}

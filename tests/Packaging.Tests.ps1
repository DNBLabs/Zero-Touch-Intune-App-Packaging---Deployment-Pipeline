<#
.SYNOPSIS
    Pester tests for New-IntuneDropWin32Package (mocked IntuneWinAppUtil process).
#>
BeforeAll {
    $repoRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $moduleManifest = Join-Path -Path $repoRoot -ChildPath 'src\Modules\IntuneDropPipeline\IntuneDropPipeline.psd1'
    Import-Module -Name $moduleManifest -Force
}

AfterAll {
    Remove-Module -Name IntuneDropPipeline -Force -ErrorAction SilentlyContinue
}

Describe 'New-IntuneDropWin32Package' {
    BeforeEach {
        $script:staging = Join-Path -Path $TestDrive -ChildPath 'staging'
        $script:prepExe = Join-Path -Path $TestDrive -ChildPath 'IntuneWinAppUtil.exe'
        New-Item -Path $script:prepExe -ItemType File -Force | Out-Null
        $script:installer = Join-Path -Path $TestDrive -ChildPath 'Vendor_App_1.0.0.msi'
        Set-Content -LiteralPath $script:installer -Value 'not-a-real-msi' -Encoding utf8
    }

    It 'throws ERR_PACKAGING when prep tool path does not exist' {
        $missingPrep = Join-Path -Path $TestDrive -ChildPath 'missing.exe'
        $err = {
            New-IntuneDropWin32Package -InstallerPath $script:installer -StagingPath $script:staging -PrepToolExe $missingPrep
        } | Should -Throw -PassThru
        $err.FullyQualifiedErrorId | Should -BeLike 'ERR_PACKAGING*'
        $err.Exception.Message | Should -Match 'Prep tool not found'
    }

    It 'throws ERR_PACKAGING when installer path is missing' {
        $missingInstaller = Join-Path -Path $TestDrive -ChildPath 'Nope_Here_1.0.msi'
        $err = {
            New-IntuneDropWin32Package -InstallerPath $missingInstaller -StagingPath $script:staging -PrepToolExe $script:prepExe
        } | Should -Throw -PassThru
        $err.FullyQualifiedErrorId | Should -BeLike 'ERR_PACKAGING*'
    }

    It 'returns IntuneWinPath when prep process exits 0 and writes one intunewin' {
        Mock -ModuleName IntuneDropPipeline -CommandName Invoke-IntuneDropIntuneWinAppUtilProcess -MockWith {
            param(
                [string]$PrepToolExe,
                [string[]]$ArgumentList,
                [string]$StandardOutputPath,
                [string]$StandardErrorPath
            )
            Set-Content -LiteralPath $StandardOutputPath -Value 'mock success'
            Set-Content -LiteralPath $StandardErrorPath -Value ''
            $outputIndex = [Array]::IndexOf($ArgumentList, '-o')
            $outDir = $ArgumentList[$outputIndex + 1]
            New-Item -Path (Join-Path $outDir 'Package.intunewin') -ItemType File -Force | Out-Null
            return 0
        }

        $result = New-IntuneDropWin32Package -InstallerPath $script:installer -StagingPath $script:staging -PrepToolExe $script:prepExe

        $result.IntuneWinPath | Should -BeLike '*\Package.intunewin'
        (Test-Path -LiteralPath $result.IntuneWinPath) | Should -Be $true
        (Test-Path -LiteralPath $result.StagedInstaller) | Should -Be $true
        $result.StagedInstaller | Should -BeLike '*\input\Vendor_App_1.0.0.msi'
    }

    It 'throws ERR_PACKAGING when prep process returns non-zero exit code' {
        Mock -ModuleName IntuneDropPipeline -CommandName Invoke-IntuneDropIntuneWinAppUtilProcess -MockWith {
            param(
                [string]$PrepToolExe,
                [string[]]$ArgumentList,
                [string]$StandardOutputPath,
                [string]$StandardErrorPath
            )
            Set-Content -LiteralPath $StandardOutputPath -Value ''
            Set-Content -LiteralPath $StandardErrorPath -Value 'tool failed'
            return 1
        }

        $err = {
            New-IntuneDropWin32Package -InstallerPath $script:installer -StagingPath $script:staging -PrepToolExe $script:prepExe
        } | Should -Throw -PassThru
        $err.FullyQualifiedErrorId | Should -BeLike 'ERR_PACKAGING*'
        $err.Exception.Message | Should -Match 'exited with code 1'
    }

    It 'throws ERR_PACKAGING when exit code is 0 but no intunewin appears' {
        Mock -ModuleName IntuneDropPipeline -CommandName Invoke-IntuneDropIntuneWinAppUtilProcess -MockWith {
            param(
                [string]$PrepToolExe,
                [string[]]$ArgumentList,
                [string]$StandardOutputPath,
                [string]$StandardErrorPath
            )
            Set-Content -LiteralPath $StandardOutputPath -Value ''
            Set-Content -LiteralPath $StandardErrorPath -Value ''
            return 0
        }

        $err = {
            New-IntuneDropWin32Package -InstallerPath $script:installer -StagingPath $script:staging -PrepToolExe $script:prepExe
        } | Should -Throw -PassThru
        $err.Exception.Message | Should -Match 'no \.intunewin file'
    }
}

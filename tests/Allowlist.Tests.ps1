<#
.SYNOPSIS
    Pester tests for Get-IntuneDropInstallIntent and allowlist matching.
#>
BeforeAll {
    $repoRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $moduleManifest = Join-Path -Path $repoRoot -ChildPath 'src\Modules\IntuneDropPipeline\IntuneDropPipeline.psd1'
    Import-Module -Name $moduleManifest -Force
}

AfterAll {
    Remove-Module -Name IntuneDropPipeline -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IntuneDropInstallIntent' {
    It 'returns MSI intent with msiexec install and ProductCode placeholder when code is omitted' {
        $package = Get-IntuneDropPackageFromFileName -FileName 'Contoso_DemoApp_1.2.3.msi'
        $intent = Get-IntuneDropInstallIntent -Package $package

        $intent.AllowlistEntryId | Should -Be 'portfolio-msi-v1'
        $intent.InstallCommandLine | Should -Be 'msiexec /i "Contoso_DemoApp_1.2.3.msi" /qn /norestart'
        $intent.UninstallCommandLine | Should -Match '\{ProductCode\}'
        $intent.DisplayName | Should -Be 'Contoso DemoApp 1.2.3'
        $intent.Detection.RuleType | Should -Be 'msiProductCode'
    }

    It 'expands ProductCode in MSI uninstall when provided' {
        $package = Get-IntuneDropPackageFromFileName -FileName 'Contoso_DemoApp_1.0.0.msi'
        $code = '{11111111-1111-1111-1111-111111111111}'
        $intent = Get-IntuneDropInstallIntent -Package $package -ProductCode $code

        $intent.UninstallCommandLine | Should -Be "msiexec /x $code /qn /norestart"
        $intent.UninstallCommandLine | Should -Not -Match '\{ProductCode\}'
    }

    It 'returns EXE intent with Inno-style switches and file detection template' {
        $package = Get-IntuneDropPackageFromFileName -FileName 'Fabrikam_Widget_2.0.exe'
        $intent = Get-IntuneDropInstallIntent -Package $package

        $intent.AllowlistEntryId | Should -Be 'portfolio-inno-style-exe-v1'
        $intent.InstallCommandLine | Should -Be '"Fabrikam_Widget_2.0.exe" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART'
        $intent.UninstallCommandLine | Should -Be '"Fabrikam_Widget_2.0.exe" /VERYSILENT /UNINSTALL'
        $intent.Detection.RuleType | Should -Be 'file'
        $intent.Detection.Path | Should -Match 'Fabrikam'
        $intent.Detection.ExpectedValue | Should -Be '2.0'
    }

    It 'throws ERR_ALLOWLIST for unsupported extension on package object' {
        $badPackage = [pscustomobject]@{
            Vendor    = 'A'
            AppName   = 'B'
            Version   = '1.0'
            Extension = 'msix'
            FileName  = 'A_B_1.0.msix'
        }

        $err = { Get-IntuneDropInstallIntent -Package $badPackage } | Should -Throw -PassThru
        $err.FullyQualifiedErrorId | Should -BeLike 'ERR_ALLOWLIST*'
        $err.Exception.Message | Should -Match 'ERR_ALLOWLIST:'
    }

    It 'throws when Package is missing FileName' {
        $incomplete = [pscustomobject]@{ Vendor = 'V'; AppName = 'A'; Version = '1.0'; Extension = 'msi' }
        { Get-IntuneDropInstallIntent -Package $incomplete } | Should -Throw '*required property*FileName*'
    }
}

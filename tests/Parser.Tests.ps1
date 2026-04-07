<#
.SYNOPSIS
    Pester tests for Get-IntuneDropPackageFromFileName convention parsing.
#>
BeforeAll {
    $repoRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $moduleManifest = Join-Path -Path $repoRoot -ChildPath 'src\Modules\IntuneDropPipeline\IntuneDropPipeline.psd1'
    Import-Module -Name $moduleManifest -Force
}

AfterAll {
    Remove-Module -Name IntuneDropPipeline -Force -ErrorAction SilentlyContinue
}

Describe 'Get-IntuneDropPackageFromFileName' {
    It 'parses a valid MSI leaf name' {
        $result = Get-IntuneDropPackageFromFileName -FileName 'Contoso_DemoApp_1.0.0.msi'
        $result.Vendor | Should -Be 'Contoso'
        $result.AppName | Should -Be 'DemoApp'
        $result.Version | Should -Be '1.0.0'
        $result.Extension | Should -Be 'msi'
        $result.FileName | Should -Be 'Contoso_DemoApp_1.0.0.msi'
    }

    It 'parses a valid EXE with two-part version' {
        $result = Get-IntuneDropPackageFromFileName -FileName 'Fabrikam_Tool_10.20.exe'
        $result.Extension | Should -Be 'exe'
        $result.Version | Should -Be '10.20'
    }

    It 'uses only the file name when a full path is supplied' {
        $path = Join-Path -Path 'D:\inbox' -ChildPath 'Vendor_App_2.3.4.5.msi'
        $result = Get-IntuneDropPackageFromFileName -FileName $path
        $result.FileName | Should -Be 'Vendor_App_2.3.4.5.msi'
        $result.Version | Should -Be '2.3.4.5'
    }

    It 'accepts extension casing mixed case' {
        $result = Get-IntuneDropPackageFromFileName -FileName 'A_B_1.0.MSI'
        $result.Extension | Should -Be 'msi'
    }

    It 'throws ERR_FILENAME_CONVENTION for setup.exe' {
        $err = { Get-IntuneDropPackageFromFileName -FileName 'setup.exe' } | Should -Throw -PassThru
        # PowerShell qualifies the id as 'Id,CommandName'
        $err.FullyQualifiedErrorId | Should -BeLike 'ERR_FILENAME_CONVENTION*'
        $err.Exception.Message | Should -Match 'ERR_FILENAME_CONVENTION:'
    }

    It 'throws ERR_FILENAME_CONVENTION when vendor or app contains an extra underscore segment' {
        $err = { Get-IntuneDropPackageFromFileName -FileName 'Contoso_Demo_App_1.0.0.msi' } | Should -Throw -PassThru
        $err.FullyQualifiedErrorId | Should -BeLike 'ERR_FILENAME_CONVENTION*'
    }

    It 'throws ERR_FILENAME_CONVENTION for empty string' {
        $err = { Get-IntuneDropPackageFromFileName -FileName '' } | Should -Throw -PassThru
        $err.FullyQualifiedErrorId | Should -BeLike 'ERR_FILENAME_CONVENTION*'
    }

    It 'pipes multiple names' {
        $results = @('V_A_1.0.msi', 'X_Y_2.0.exe') | Get-IntuneDropPackageFromFileName
        $results | Should -HaveCount 2
        $results[0].Vendor | Should -Be 'V'
        $results[1].AppName | Should -Be 'Y'
    }
}

<#
.SYNOPSIS
    Pester tests for ConvertTo-IntuneDropWin32LobCreateBody Graph rule shapes (win32LobAppRule vs legacy *Detection).
#>
BeforeAll {
    $repoRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $moduleManifest = Join-Path -Path $repoRoot -ChildPath 'src\Modules\IntuneDropPipeline\IntuneDropPipeline.psd1'
    Import-Module -Name $moduleManifest -Force
}

AfterAll {
    Remove-Module -Name IntuneDropPipeline -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-IntuneDropWin32LobCreateBody' {
    It 'emits win32LobAppFileSystemRule entries for file detection (not FileSystemDetection)' {
        $package = Get-IntuneDropPackageFromFileName -FileName 'Fabrikam_App_2.0.exe'
        $intent = Get-IntuneDropInstallIntent -Package $package

        InModuleScope -ModuleName 'IntuneDropPipeline' -ScriptBlock {
            param($I, $Meta, $Fn, $Len)
            $body = ConvertTo-IntuneDropWin32LobCreateBody -InstallIntent $I -IntuneWinMetadata $Meta -IntuneWinFileName $Fn -IntuneWinFileLengthBytes $Len
            $rule = $body.rules[0]
            $rule.'@odata.type' | Should -Be '#microsoft.graph.win32LobAppFileSystemRule'
            $rule.ruleType | Should -Be 'detection'
            $rule.operationType | Should -Be 'version'
            $rule.operator | Should -Be 'greaterThanOrEqual'
            $rule.comparisonValue | Should -Be '2.0'
            $rule.PSObject.Properties.Name | Should -Not -Contain 'detectionType'
            $body.minimumSupportedWindowsRelease | Should -Be 'Windows10_22H2'
            $body.applicableArchitectures | Should -Be 'x64'
            $body.allowedArchitectures | Should -Be 'x64'
            $body.Keys | Should -Not -Contain 'size'
            $body.installExperience.Keys | Should -Not -Contain 'maxRunTimeInMinutes'
        } -ArgumentList $intent, ([pscustomobject]@{
                SetupFileName          = 'Fabrikam_App_2.0.exe'
                UnencryptedContentSize = [long]999
                FileEncryptionInfo     = @{}
            }), 'out.intunewin', ([long]1000)
    }

    It 'emits win32LobAppProductCodeRule for MSI detection' {
        $package = Get-IntuneDropPackageFromFileName -FileName 'Contoso_Demo_1.0.0.msi'
        $code = '{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}'
        $intent = Get-IntuneDropInstallIntent -Package $package -ProductCode $code

        InModuleScope -ModuleName 'IntuneDropPipeline' -ScriptBlock {
            param($I, $Meta, $Fn, $Len)
            $body = ConvertTo-IntuneDropWin32LobCreateBody -InstallIntent $I -IntuneWinMetadata $Meta -IntuneWinFileName $Fn -IntuneWinFileLengthBytes $Len
            $rule = $body.rules[0]
            $rule.'@odata.type' | Should -Be '#microsoft.graph.win32LobAppProductCodeRule'
            $rule.ruleType | Should -Be 'detection'
            $rule.productCode | Should -Be '{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}'
            $rule.productVersionOperator | Should -Be 'notConfigured'
        } -ArgumentList $intent, ([pscustomobject]@{
                SetupFileName          = 'x.msi'
                UnencryptedContentSize = [long]1
                FileEncryptionInfo     = @{}
            }), 'p.intunewin', ([long]2)
    }
}

<#
.SYNOPSIS
    Pester tests for Resolve-IntuneDropManagedPaths staging defaults (IntuneWinAppUtil path safety).
#>
BeforeAll {
    $repoRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $moduleManifest = Join-Path -Path $repoRoot -ChildPath 'src\Modules\IntuneDropPipeline\IntuneDropPipeline.psd1'
    Import-Module -Name $moduleManifest -Force
}

AfterAll {
    Remove-Module -Name IntuneDropPipeline -Force -ErrorAction SilentlyContinue
}

Describe 'Resolve-IntuneDropManagedPaths' {
    BeforeEach {
        $script:managedPathsSavedStaging = [Environment]::GetEnvironmentVariable('INTUNE_DROP_STAGING_PATH', 'Process')
        Remove-Item Env:INTUNE_DROP_STAGING_PATH -ErrorAction SilentlyContinue
    }

    AfterEach {
        if ($null -eq $script:managedPathsSavedStaging -or $script:managedPathsSavedStaging -eq '') {
            Remove-Item Env:INTUNE_DROP_STAGING_PATH -ErrorAction SilentlyContinue
        }
        else {
            $env:INTUNE_DROP_STAGING_PATH = $script:managedPathsSavedStaging
        }
    }

    It 'places default staging under the repository when the path has no ampersand' {
        InModuleScope IntuneDropPipeline {
            $repo = 'C:\FakeRepo\PortfolioProject'
            $paths = Resolve-IntuneDropManagedPaths -RepositoryRoot $repo
            $expected = [System.IO.Path]::GetFullPath((Join-Path -Path $repo -ChildPath 'staging'))
            $paths['INTUNE_DROP_STAGING_PATH'] | Should -Be $expected
        }
    }

    It 'uses LocalApplicationData\IntuneDropPipeline\staging when repository path contains ampersand' {
        InModuleScope IntuneDropPipeline {
            $repo = 'C:\Users\Example\Projects\Packaging & Deployment\repo'
            $paths = Resolve-IntuneDropManagedPaths -RepositoryRoot $repo
            $staging = $paths['INTUNE_DROP_STAGING_PATH']
            $staging | Should -Match ([regex]::Escape('IntuneDropPipeline'))
            (Split-Path -Path $staging -Leaf) | Should -Be 'staging'
            $staging | Should -Not -Match '&'
            $local = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
            [System.IO.Path]::GetFullPath($staging).StartsWith(
                [System.IO.Path]::GetFullPath($local) + [System.IO.Path]::DirectorySeparatorChar,
                [System.StringComparison]::OrdinalIgnoreCase
            ) | Should -Be $true
        }
    }

    It 'still allows INTUNE_DROP_STAGING_PATH to override the ampersand-safe default' {
        InModuleScope IntuneDropPipeline {
            $repo = 'D:\bad & path\repo'
            $custom = 'C:\CustomStagingRoot\staging'
            $env:INTUNE_DROP_STAGING_PATH = $custom
            $paths = Resolve-IntuneDropManagedPaths -RepositoryRoot $repo
            $paths['INTUNE_DROP_STAGING_PATH'] | Should -Be ([System.IO.Path]::GetFullPath($custom))
        }
    }
}

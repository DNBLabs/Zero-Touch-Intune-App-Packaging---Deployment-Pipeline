<#
.SYNOPSIS
    Ensures PSScriptAnalyzer reports no Error-severity issues for src/ when using the repository settings file.
#>
BeforeDiscovery {
    $script:hasScriptAnalyzerModule = $null -ne (Get-Module -ListAvailable -Name PSScriptAnalyzer)
}

BeforeAll {
    $script:repoRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $script:settingsPath = Join-Path -Path $repoRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
    $script:srcPath = Join-Path -Path $repoRoot -ChildPath 'src'
}

Describe 'PSScriptAnalyzer repository settings' {
    It 'reports zero Error severity for src when settings file is used' -Skip:(-not $script:hasScriptAnalyzerModule) {
        Import-Module -Name PSScriptAnalyzer -Force

        $findings = Invoke-ScriptAnalyzer -Path $script:srcPath -Recurse -Settings $script:settingsPath -Severity Error |
            Where-Object -FilterScript { $_.Severity -eq 'Error' }

        $findings | Should -BeNullOrEmpty
    }
}

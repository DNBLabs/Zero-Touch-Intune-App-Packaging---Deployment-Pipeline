<#
.SYNOPSIS
    Loads pipeline configuration from environment variables and optional path overrides.
.DESCRIPTION
    Resolves managed folder paths (defaults relative to the repository root, then config.local.json for path keys only, then process environment variables). Reads Microsoft Graph and packaging settings strictly from process environment variables. Throws if any required variable is missing or blank; the error lists only variable names, never secret values.
.OUTPUTS
    [pscustomobject] Configuration with RepositoryRoot, path properties, PrepToolExe, TestGroupId, and Azure AD application identifiers.
#>
function Get-IntuneDropConfiguration {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $requiredEnvKeys = @(
        'INTUNE_DROP_PREP_TOOL_EXE',
        'INTUNE_DROP_TEST_GROUP_ID',
        'AZURE_TENANT_ID',
        'AZURE_CLIENT_ID',
        'AZURE_CLIENT_SECRET'
    )

    $repositoryRoot = Get-IntuneDropRepositoryRoot
    $managedPaths = Resolve-IntuneDropManagedPaths -RepositoryRoot $repositoryRoot

    $missingKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $requiredEnvKeys) {
        $value = [Environment]::GetEnvironmentVariable($key, 'Process')
        if ([string]::IsNullOrWhiteSpace($value)) {
            $missingKeys.Add($key) | Out-Null
        }
    }

    if ($missingKeys.Count -gt 0) {
        $sorted = $missingKeys | Sort-Object
        $names = $sorted -join ', '
        throw "Missing required environment variables: $names"
    }

    [pscustomobject]@{
        RepositoryRoot     = $repositoryRoot
        InboxPath          = $managedPaths['INTUNE_DROP_INBOX_PATH']
        DonePath           = $managedPaths['INTUNE_DROP_DONE_PATH']
        FailedPath         = $managedPaths['INTUNE_DROP_FAILED_PATH']
        StagingPath        = $managedPaths['INTUNE_DROP_STAGING_PATH']
        PrepToolExe        = [Environment]::GetEnvironmentVariable('INTUNE_DROP_PREP_TOOL_EXE', 'Process')
        TestGroupId        = [Environment]::GetEnvironmentVariable('INTUNE_DROP_TEST_GROUP_ID', 'Process')
        AzureTenantId      = [Environment]::GetEnvironmentVariable('AZURE_TENANT_ID', 'Process')
        AzureClientId      = [Environment]::GetEnvironmentVariable('AZURE_CLIENT_ID', 'Process')
        AzureClientSecret  = [Environment]::GetEnvironmentVariable('AZURE_CLIENT_SECRET', 'Process')
    }
}

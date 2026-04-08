<#
.SYNOPSIS
    Loads pipeline configuration from environment variables and optional path overrides.
.DESCRIPTION
    Resolves managed folder paths (defaults relative to the repository root, then config.local.json for path keys only, then process environment variables). Reads Microsoft Graph and packaging settings strictly from process environment variables. Graph application auth must be exactly one of: AZURE_CLIENT_SECRET (legacy), AZURE_CLIENT_CERTIFICATE_THUMBPRINT (Windows cert store), or AZURE_CLIENT_CERTIFICATE_PATH (PFX file). Throws if any required variable is missing or ambiguous; the error lists only variable names or safe messages, never secret values.
.OUTPUTS
    [pscustomobject] Configuration with RepositoryRoot, path properties, PrepToolExe, TestGroupId, Azure AD application identifiers, and optional certificate fields.
#>
function Get-IntuneDropConfiguration {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $requiredEnvKeys = @(
        'INTUNE_DROP_PREP_TOOL_EXE',
        'INTUNE_DROP_TEST_GROUP_ID',
        'AZURE_TENANT_ID',
        'AZURE_CLIENT_ID'
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

    $secret = [Environment]::GetEnvironmentVariable('AZURE_CLIENT_SECRET', 'Process')
    $thumbprint = [Environment]::GetEnvironmentVariable('AZURE_CLIENT_CERTIFICATE_THUMBPRINT', 'Process')
    $certificatePath = [Environment]::GetEnvironmentVariable('AZURE_CLIENT_CERTIFICATE_PATH', 'Process')

    $hasSecret = -not [string]::IsNullOrWhiteSpace($secret)
    $hasThumbprint = -not [string]::IsNullOrWhiteSpace($thumbprint)
    $hasCertificatePath = -not [string]::IsNullOrWhiteSpace($certificatePath)

    $credentialModeCount = 0
    if ($hasSecret) { $credentialModeCount++ }
    if ($hasThumbprint) { $credentialModeCount++ }
    if ($hasCertificatePath) { $credentialModeCount++ }

    if ($credentialModeCount -eq 0) {
        throw 'Missing Graph application credential. Set exactly one of AZURE_CLIENT_SECRET, AZURE_CLIENT_CERTIFICATE_THUMBPRINT, or AZURE_CLIENT_CERTIFICATE_PATH.'
    }

    if ($credentialModeCount -gt 1) {
        throw 'Ambiguous Graph application credential: set only one of AZURE_CLIENT_SECRET, AZURE_CLIENT_CERTIFICATE_THUMBPRINT, or AZURE_CLIENT_CERTIFICATE_PATH.'
    }

    [pscustomobject]@{
        RepositoryRoot                     = $repositoryRoot
        InboxPath                         = $managedPaths['INTUNE_DROP_INBOX_PATH']
        DonePath                          = $managedPaths['INTUNE_DROP_DONE_PATH']
        FailedPath                        = $managedPaths['INTUNE_DROP_FAILED_PATH']
        StagingPath                       = $managedPaths['INTUNE_DROP_STAGING_PATH']
        PrepToolExe                       = [Environment]::GetEnvironmentVariable('INTUNE_DROP_PREP_TOOL_EXE', 'Process')
        TestGroupId                       = [Environment]::GetEnvironmentVariable('INTUNE_DROP_TEST_GROUP_ID', 'Process')
        AzureTenantId                     = [Environment]::GetEnvironmentVariable('AZURE_TENANT_ID', 'Process')
        AzureClientId                     = [Environment]::GetEnvironmentVariable('AZURE_CLIENT_ID', 'Process')
        AzureClientSecret                 = if ($hasSecret) { $secret } else { $null }
        AzureClientCertificateThumbprint = if ($hasThumbprint) { $thumbprint.Trim() } else { $null }
        AzureClientCertificatePath        = if ($hasCertificatePath) { $certificatePath.Trim() } else { $null }
        AzureClientCertificatePassword    = [Environment]::GetEnvironmentVariable('AZURE_CLIENT_CERTIFICATE_PASSWORD', 'Process')
    }
}

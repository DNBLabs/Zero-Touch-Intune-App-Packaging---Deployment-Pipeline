<#
.SYNOPSIS
    Builds resolved inbox, done, failed, and staging paths using defaults, optional config.local.json, and process environment variables.
.PARAMETER RepositoryRoot
    Absolute path to the repository root (contains inbox/, docs/, etc.).
.OUTPUTS
    Hashtable with keys INTUNE_DROP_INBOX_PATH, INTUNE_DROP_DONE_PATH, INTUNE_DROP_FAILED_PATH, INTUNE_DROP_STAGING_PATH.
.DESCRIPTION
    Merge order: repository defaults, then non-secret keys from config.local.json at the repo root if present, then process environment variables for those keys (environment wins).
#>
function Resolve-IntuneDropManagedPaths {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    $pathKeyNames = @(
        'INTUNE_DROP_INBOX_PATH',
        'INTUNE_DROP_DONE_PATH',
        'INTUNE_DROP_FAILED_PATH',
        'INTUNE_DROP_STAGING_PATH'
    )

    $pathValues = @{}
    $pathValues['INTUNE_DROP_INBOX_PATH'] = Join-Path -Path $RepositoryRoot -ChildPath 'inbox'
    $pathValues['INTUNE_DROP_DONE_PATH'] = Join-Path -Path $RepositoryRoot -ChildPath 'done'
    $pathValues['INTUNE_DROP_FAILED_PATH'] = Join-Path -Path $RepositoryRoot -ChildPath 'failed'
    $pathValues['INTUNE_DROP_STAGING_PATH'] = Join-Path -Path $RepositoryRoot -ChildPath 'staging'

    $localConfigPath = Join-Path -Path $RepositoryRoot -ChildPath 'config.local.json'
    if (Test-Path -LiteralPath $localConfigPath) {
        try {
            $jsonRaw = Get-Content -LiteralPath $localConfigPath -Raw -ErrorAction Stop
            $localObject = $jsonRaw | ConvertFrom-Json -ErrorAction Stop
            foreach ($prop in $localObject.PSObject.Properties) {
                if ($pathKeyNames -contains $prop.Name) {
                    $value = [string]$prop.Value
                    if (-not [string]::IsNullOrWhiteSpace($value)) {
                        $pathValues[$prop.Name] = $value
                    }
                }
            }
        }
        catch {
            throw "Failed to read path overrides from config.local.json at '$localConfigPath': $($_.Exception.Message)"
        }
    }

    foreach ($key in $pathKeyNames) {
        $fromEnv = [Environment]::GetEnvironmentVariable($key, 'Process')
        if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
            $pathValues[$key] = $fromEnv
        }
    }

    foreach ($key in $pathKeyNames) {
        $pathValues[$key] = [System.IO.Path]::GetFullPath($pathValues[$key])
    }

    return $pathValues
}

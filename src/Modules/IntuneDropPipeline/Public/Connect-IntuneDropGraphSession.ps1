<#
.SYNOPSIS
    Connects to Microsoft Graph using an Entra app registration (certificate preferred, or client secret for legacy use).
.DESCRIPTION
    Requires modules Microsoft.Graph.Authentication (and Microsoft.Graph on some installs). Uses application-only context suitable for unattended packaging hosts. When configuration supplies a certificate thumbprint or PFX path, Connect-MgGraph uses certificate auth; otherwise AZURE_CLIENT_SECRET is used.
.PARAMETER UseConfiguration
    Reads AZURE_TENANT_ID, AZURE_CLIENT_ID, and one of AZURE_CLIENT_CERTIFICATE_THUMBPRINT / AZURE_CLIENT_CERTIFICATE_PATH / AZURE_CLIENT_SECRET from Get-IntuneDropConfiguration.
.PARAMETER TenantId
    Directory (tenant) GUID when using explicit secret credentials.
.PARAMETER ClientId
    Application (client) ID.
.PARAMETER ClientSecret
    Client secret string (handle only via secure environment configuration). Used only with the ExplicitSecret parameter set.
#>
function Connect-IntuneDropGraphSession {
    [CmdletBinding(DefaultParameterSetName = 'Configuration')]
    param(
        [Parameter(ParameterSetName = 'Configuration')]
        [switch] $UseConfiguration,

        [Parameter(ParameterSetName = 'ExplicitSecret', Mandatory)]
        [string] $TenantId,

        [Parameter(ParameterSetName = 'ExplicitSecret', Mandatory)]
        [string] $ClientId,

        [Parameter(ParameterSetName = 'ExplicitSecret', Mandatory)]
        [string] $ClientSecret
    )

    $null = $UseConfiguration

    $configuration = $null
    if ($PSCmdlet.ParameterSetName -eq 'Configuration') {
        $configuration = Get-IntuneDropConfiguration
        $TenantId = $configuration.AzureTenantId
        $ClientId = $configuration.AzureClientId
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    if (-not (Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue)) {
        Import-Module Microsoft.Graph -ErrorAction Stop
    }

    try {
        if ($PSCmdlet.ParameterSetName -eq 'ExplicitSecret') {
            $secureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
            $applicationCredential = [pscredential]::new($ClientId, $secureSecret)
            Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $applicationCredential -NoWelcome -ErrorAction Stop
            return
        }

        if (-not [string]::IsNullOrWhiteSpace($configuration.AzureClientCertificateThumbprint) -or
            -not [string]::IsNullOrWhiteSpace($configuration.AzureClientCertificatePath)) {
            $certificate = Resolve-IntuneDropGraphCertificate -Configuration $configuration
            try {
                Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -Certificate $certificate -NoWelcome -ErrorAction Stop
            }
            finally {
                $certificate.Dispose()
            }
            return
        }

        $secretValue = $configuration.AzureClientSecret
        if ([string]::IsNullOrWhiteSpace($secretValue)) {
            throw 'Get-IntuneDropConfiguration returned no client secret and no certificate; credential validation should have prevented this.'
        }

        $secureSecret = ConvertTo-SecureString -String $secretValue -AsPlainText -Force
        $applicationCredential = [pscredential]::new($ClientId, $secureSecret)
        Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $applicationCredential -NoWelcome -ErrorAction Stop
    }
    catch {
        $surfaceMessage = $_.Exception.Message
        if ($surfaceMessage.Length -gt 2000) {
            $surfaceMessage = $surfaceMessage.Substring(0, 2000) + '...'
        }
        $record = New-IntuneDropGraphErrorRecord -Message "Connect-MgGraph failed: $surfaceMessage" -TargetObject $TenantId
        $PSCmdlet.ThrowTerminatingError($record)
    }
}

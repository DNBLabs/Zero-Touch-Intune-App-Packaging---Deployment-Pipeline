<#
.SYNOPSIS
    Connects to Microsoft Graph using an Azure AD application registration (client secret).
.DESCRIPTION
    Requires modules Microsoft.Graph.Authentication (and Invoke-MgGraphRequest from Microsoft.Graph on some installs). Uses application-only context suitable for unattended packaging hosts.
.PARAMETER UseConfiguration
    Reads AZURE_TENANT_ID, AZURE_CLIENT_ID, and AZURE_CLIENT_SECRET from Get-IntuneDropConfiguration (environment variables).
.PARAMETER TenantId
    Directory (tenant) GUID when using explicit credentials.
.PARAMETER ClientId
    Application (client) ID.
.PARAMETER ClientSecret
    Client secret string (handle only via secure environment configuration).
#>
function Connect-IntuneDropGraphSession {
    [CmdletBinding(DefaultParameterSetName = 'Configuration')]
    param(
        [Parameter(ParameterSetName = 'Configuration')]
        [switch] $UseConfiguration,

        [Parameter(ParameterSetName = 'Explicit', Mandatory)]
        [string] $TenantId,

        [Parameter(ParameterSetName = 'Explicit', Mandatory)]
        [string] $ClientId,

        [Parameter(ParameterSetName = 'Explicit', Mandatory)]
        [string] $ClientSecret
    )

    if ($PSCmdlet.ParameterSetName -eq 'Configuration') {
        $configuration = Get-IntuneDropConfiguration
        $TenantId = $configuration.AzureTenantId
        $ClientId = $configuration.AzureClientId
        $ClientSecret = $configuration.AzureClientSecret
    }

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    if (-not (Get-Command -Name Connect-MgGraph -ErrorAction SilentlyContinue)) {
        Import-Module Microsoft.Graph -ErrorAction Stop
    }

    try {
        $secureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
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

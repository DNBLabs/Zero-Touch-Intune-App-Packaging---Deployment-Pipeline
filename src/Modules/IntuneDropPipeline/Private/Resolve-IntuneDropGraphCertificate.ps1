<#
.SYNOPSIS
    Builds an X509Certificate2 for Connect-MgGraph from the pipeline configuration (PFX path or store thumbprint).
.DESCRIPTION
    Thumbprints are resolved from Cert:\CurrentUser\My first, then Cert:\LocalMachine\My. PFX paths use optional AZURE_CLIENT_CERTIFICATE_PASSWORD and EphemeralKeySet when available to avoid persisting keys.
.PARAMETER Configuration
    Object returned by Get-IntuneDropConfiguration with certificate fields populated.
.OUTPUTS
    System.Security.Cryptography.X509Certificates.X509Certificate2. Caller must Dispose() after Connect-MgGraph succeeds.
#>
function Resolve-IntuneDropGraphCertificate {
    [CmdletBinding()]
    [OutputType([System.Security.Cryptography.X509Certificates.X509Certificate2])]
    param(
        [Parameter(Mandatory)]
        [psobject] $Configuration
    )

    $pfxPath = $Configuration.AzureClientCertificatePath
    if (-not [string]::IsNullOrWhiteSpace($pfxPath)) {
        $fullPath = [System.IO.Path]::GetFullPath($pfxPath.Trim())
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "PFX for Graph authentication was not found at '$fullPath'."
        }

        $password = $Configuration.AzureClientCertificatePassword
        if ($null -eq $password) {
            $password = [string]::Empty
        }

        $storageFlags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet

        return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($fullPath, $password, $storageFlags)
    }

    $thumbprint = $Configuration.AzureClientCertificateThumbprint
    if (-not [string]::IsNullOrWhiteSpace($thumbprint)) {
        $normalized = ($thumbprint.Trim() -replace '\s').ToUpperInvariant()
        foreach ($locationName in @('CurrentUser', 'LocalMachine')) {
            $storePath = Join-Path -Path 'Cert:' -ChildPath ($locationName + '\My')
            $matches = @(Get-ChildItem -Path $storePath -ErrorAction SilentlyContinue | Where-Object { $null -ne $_.Thumbprint -and ($_.Thumbprint.ToUpperInvariant() -eq $normalized) })
            if ($matches.Count -gt 0) {
                return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($matches[0].RawData)
            }
        }

        throw "No certificate with thumbprint '$normalized' was found under Cert:\CurrentUser\My or Cert:\LocalMachine\My."
    }

    throw 'Configuration does not specify AZURE_CLIENT_CERTIFICATE_PATH or AZURE_CLIENT_CERTIFICATE_THUMBPRINT.'
}

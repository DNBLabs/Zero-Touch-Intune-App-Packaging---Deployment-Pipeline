<#
.SYNOPSIS
    Invokes Microsoft Graph HTTP APIs using Invoke-MgGraphRequest (mockable in Pester tests).
.PARAMETER Method
    HTTP verb.
.PARAMETER Uri
    Request URI (absolute https://graph.microsoft.com/... recommended for beta).
.PARAMETER Body
    Object to convert to JSON, a JSON string, or $null for body-less requests.
.PARAMETER ContentType
    Defaults to application/json when Body is set.
#>
function Invoke-IntuneDropGraphRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'PUT', 'DELETE')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Uri,

        [Parameter()]
        [object] $Body,

        [Parameter()]
        [string] $ContentType = 'application/json'
    )

    Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
    if (-not (Get-Command -Name Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
        Import-Module Microsoft.Graph -ErrorAction Stop
    }

    $graphContext = Get-MgContext -ErrorAction SilentlyContinue
    if ($null -eq $graphContext) {
        $record = New-IntuneDropGraphErrorRecord -Message 'Not connected to Microsoft Graph. Call Connect-IntuneDropGraphSession first.' -TargetObject $Uri
        $PSCmdlet.ThrowTerminatingError($record)
    }

    try {
        $invokeParams = @{
            Method = $Method
            Uri    = $Uri
        }

        if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
            if ($Body -is [string]) {
                $invokeParams.Body = $Body
            }
            else {
                $invokeParams.Body = $Body | ConvertTo-Json -Depth 30 -Compress
            }
            $invokeParams.ContentType = $ContentType
        }

        # #region agent log
        try {
            if ($Method -eq 'POST' -and $Uri -like '*deviceAppManagement/mobileApps*' -and -not ($Uri -match '/mobileApps/[^/]+/')) {
                $dbgRepoRoot = Get-IntuneDropRepositoryRoot
                $dbgPath = Join-Path -Path $dbgRepoRoot -ChildPath 'debug-7596d3.log'
                $rawBody = $invokeParams.Body
                if ($rawBody -isnot [string]) {
                    $rawBody = $rawBody | ConvertTo-Json -Depth 30 -Compress
                }
                $maxPrefix = [Math]::Min(4000, $rawBody.Length)
                $odataTypes = [regex]::Matches($rawBody, '"@odata\.type"\s*:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
                $dbgPayload = [ordered]@{
                    sessionId    = '7596d3'
                    timestamp    = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
                    hypothesisId = 'H2,H5,H9,H10,H11'
                    location     = 'Invoke-IntuneDropGraphRequest:before Invoke-MgGraphRequest'
                    message      = 'POST mobileApps JSON shape'
                    data         = [ordered]@{
                        graphApiVersion = if ($Uri -match 'https://graph\.microsoft\.com/(?<ver>v1\.0|beta)/') { $Matches['ver'] } else { $null }
                        jsonLength      = $rawBody.Length
                        jsonPrefix      = $rawBody.Substring(0, $maxPrefix)
                        odataTypeTokens = @($odataTypes | Select-Object -Unique)
                        uriLastSegment  = ($Uri -split '/')[-1]
                    }
                }
                Add-Content -LiteralPath $dbgPath -Value ($dbgPayload | ConvertTo-Json -Compress -Depth 10) -Encoding utf8
            }
        }
        catch { }
        # #endregion

        return Invoke-MgGraphRequest @invokeParams
    }
    catch {
        $parts = [System.Collections.Generic.List[string]]::new()
        $parts.Add($_.Exception.Message)
        if ($null -ne $_.ErrorDetails -and -not [string]::IsNullOrWhiteSpace([string]$_.ErrorDetails.Message)) {
            $parts.Add([string]$_.ErrorDetails.Message.Trim())
        }
        $safe = (($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -Unique) -join ' | '
        if ($safe.Length -gt 6000) {
            $safe = $safe.Substring(0, 6000) + '...'
        }
        $record = New-IntuneDropGraphErrorRecord -Message "Graph request failed ($Method $Uri): $safe" -TargetObject $Uri
        $PSCmdlet.ThrowTerminatingError($record)
    }
}

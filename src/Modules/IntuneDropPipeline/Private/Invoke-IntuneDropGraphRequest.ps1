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

        $graphResult = Invoke-MgGraphRequest @invokeParams

        return $graphResult
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

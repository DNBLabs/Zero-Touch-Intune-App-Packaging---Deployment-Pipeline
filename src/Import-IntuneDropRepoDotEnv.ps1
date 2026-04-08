<#
.SYNOPSIS
    Applies KEY=VALUE lines from a repository .env file to the current process environment.
.DESCRIPTION
    Reads .env at the repository root (non-secret path names only). Skips blank lines and lines starting with #. Each other line must contain =; the name is trimmed and the value is the remainder after the first = (leading/trailing spaces trimmed). Does nothing if .env is missing.
.PARAMETER RepositoryRoot
    Absolute path to the repository root directory that contains .env.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $RepositoryRoot
)

$envPath = Join-Path -Path $RepositoryRoot -ChildPath '.env'
if (-not (Test-Path -LiteralPath $envPath)) {
    return
}

Get-Content -LiteralPath $envPath | ForEach-Object {
    $trimmed = $_.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#')) {
        return
    }

    $eq = $trimmed.IndexOf('=')
    if ($eq -lt 1) {
        return
    }

    $name = $trimmed.Substring(0, $eq).Trim()
    $value = $trimmed.Substring($eq + 1).Trim()
    if ($name.Length -eq 0) {
        return
    }

    Set-Item -Path "Env:$name" -Value $value
}

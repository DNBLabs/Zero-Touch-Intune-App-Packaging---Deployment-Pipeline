<#
.SYNOPSIS
    Loads KEY=value lines from a .env file into the current process environment variables.
.DESCRIPTION
    PowerShell does not read .env files automatically. This script parses simple NAME=value lines (first '=' separates name from value), skips blank lines and #-prefixed comments, and calls Set-Item Env:. Values are not written to the host. Use from the repo root or pass -LiteralPath to your .env file.
.PARAMETER LiteralPath
    Full path to the env file. Defaults to .env next to the repository root (parent of the tools folder).
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string] $LiteralPath = $(Join-Path -Path (Split-Path -LiteralPath $PSScriptRoot -Parent) -ChildPath '.env')
)

function Set-IntuneDropEnvLine {
    <#
    .SYNOPSIS
        Applies one non-comment .env line to the process environment.
    .PARAMETER Line
        A single line from the env file (may be empty or a comment).
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string] $Line
    )

    if ($null -eq $Line) {
        return
    }

    $trimmed = $Line.Trim()
    if ($trimmed -eq '' -or $trimmed.StartsWith('#')) {
        return
    }

    $equalsIndex = $trimmed.IndexOf('=')
    if ($equalsIndex -lt 1) {
        return
    }

    $name = $trimmed.Substring(0, $equalsIndex).Trim()
    if ($name -eq '') {
        return
    }

    $value = $trimmed.Substring($equalsIndex + 1).Trim()
    Set-Item -Path "Env:$name" -Value $value
}

if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
    throw "Env file not found: '$LiteralPath'"
}

Get-Content -LiteralPath $LiteralPath -Encoding utf8 | ForEach-Object {
    Set-IntuneDropEnvLine -Line $_
}

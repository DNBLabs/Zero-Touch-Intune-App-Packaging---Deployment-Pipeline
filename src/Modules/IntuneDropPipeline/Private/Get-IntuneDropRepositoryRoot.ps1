<#
.SYNOPSIS
    Resolves the repository root directory used for default inbox, staging, and documentation paths.
.DESCRIPTION
    The module lives under src/Modules/IntuneDropPipeline; the repository root is four parent levels above this file's directory (Private -> module -> Modules -> src -> repo).
#>
function Get-IntuneDropRepositoryRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $privateScriptRoot = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($privateScriptRoot)) {
        throw 'Cannot resolve repository root because PSScriptRoot is empty.'
    }

    $relativeToRepo = Join-Path -Path $privateScriptRoot -ChildPath '..\..\..\..'
    $resolved = Resolve-Path -LiteralPath $relativeToRepo -ErrorAction Stop
    return $resolved.ProviderPath
}

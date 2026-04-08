<#
.SYNOPSIS
    Moves a processed installer into done/ or failed/ and optionally writes a short reason file next to failures.
.PARAMETER SourcePath
    Absolute path to the installer that was processed.
.PARAMETER DestinationDirectory
    Root directory (done or failed).
.PARAMETER FailureReason
    When set, indicates failure handling: writes SourceName.reason.txt beside the moved file.
#>
function Move-IntuneDropInstallerToOutcomeFolder {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $SourcePath,

        [Parameter(Mandatory)]
        [string] $DestinationDirectory,

        [Parameter()]
        [string] $FailureReason
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Cannot move missing file '$SourcePath'."
    }

    $destinationRoot = [System.IO.Path]::GetFullPath($DestinationDirectory)
    $null = New-Item -ItemType Directory -Path $destinationRoot -Force -ErrorAction Stop

    $leafName = [System.IO.Path]::GetFileName($SourcePath)
    $targetPath = Join-Path -Path $destinationRoot -ChildPath $leafName

    if (Test-Path -LiteralPath $targetPath) {
        $stamp = Get-Date -Format 'yyyyMMddHHmmssfff'
        $base = [System.IO.Path]::GetFileNameWithoutExtension($leafName)
        $ext = [System.IO.Path]::GetExtension($leafName)
        $targetPath = Join-Path -Path $destinationRoot -ChildPath "${base}_${stamp}${ext}"
    }

    Move-Item -LiteralPath $SourcePath -Destination $targetPath -Force -ErrorAction Stop

    if (-not [string]::IsNullOrWhiteSpace($FailureReason)) {
        $reasonPath = "$targetPath.reason.txt"
        $trimmed = $FailureReason
        if ($trimmed.Length -gt 16000) {
            $trimmed = $trimmed.Substring(0, 16000) + [Environment]::NewLine + '... (truncated)'
        }
        Set-Content -LiteralPath $reasonPath -Value $trimmed -Encoding utf8 -Force
    }

    return [string](Resolve-Path -LiteralPath $targetPath).Path
}

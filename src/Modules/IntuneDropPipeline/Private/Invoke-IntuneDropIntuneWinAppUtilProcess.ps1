<#
.SYNOPSIS
    Starts the Microsoft Win32 Content Prep Tool (IntuneWinAppUtil.exe) and waits for completion.
.PARAMETER PrepToolExe
    Full path to IntuneWinAppUtil.exe.
.PARAMETER ArgumentList
    Argument tokens passed to the prep tool (for example -c, folder, -s, file, -o, folder).
.PARAMETER StandardOutputPath
    File path to capture stdout.
.PARAMETER StandardErrorPath
    File path to capture stderr.
.OUTPUTS
    System.Int32 exit code from the process.
#>
function Invoke-IntuneDropIntuneWinAppUtilProcess {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $PrepToolExe,

        [Parameter(Mandatory)]
        [string[]] $ArgumentList,

        [Parameter(Mandatory)]
        [string] $StandardOutputPath,

        [Parameter(Mandatory)]
        [string] $StandardErrorPath
    )

    $proc = Microsoft.PowerShell.Management\Start-Process `
        -FilePath $PrepToolExe `
        -ArgumentList $ArgumentList `
        -Wait `
        -PassThru `
        -NoNewWindow `
        -RedirectStandardOutput $StandardOutputPath `
        -RedirectStandardError $StandardErrorPath

    return $proc.ExitCode
}

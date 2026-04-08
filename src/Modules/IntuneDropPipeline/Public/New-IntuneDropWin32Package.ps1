<#
.SYNOPSIS
    Runs IntuneWinAppUtil.exe to produce a .intunewin package from a single installer file.
.DESCRIPTION
    Creates an isolated job folder under StagingPath (input + output + logs), copies the installer into the input folder, invokes the prep tool with -c, -s, and -o, then returns the path to the generated .intunewin file. Failures surface ERR_PACKAGING with details; stdout and stderr are written next to the job for troubleshooting.
.PARAMETER InstallerPath
    Full path to the .msi or .exe dropped for packaging.
.PARAMETER StagingPath
    Root folder for packaging jobs (typically from Get-IntuneDropConfiguration). A unique subfolder is created per invocation.
.PARAMETER PrepToolExe
    Full path to IntuneWinAppUtil.exe (typically from Get-IntuneDropConfiguration).
.OUTPUTS
    PSCustomObject with IntuneWinPath, JobRoot, InputDirectory, OutputDirectory, StdOutLog, StdErrLog.

.EXAMPLE
    $c = Get-IntuneDropConfiguration
    New-IntuneDropWin32Package -InstallerPath (Join-Path $c.InboxPath 'Contoso_App_1.0.0.msi') -StagingPath $c.StagingPath -PrepToolExe $c.PrepToolExe
#>
function New-IntuneDropWin32Package {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $InstallerPath,

        [Parameter(Mandatory)]
        [string] $StagingPath,

        [Parameter(Mandatory)]
        [string] $PrepToolExe
    )

    if (-not (Test-Path -LiteralPath $PrepToolExe -PathType Leaf)) {
        $record = New-IntuneDropPackagingErrorRecord -Message "Prep tool not found at '$PrepToolExe'." -TargetObject $PrepToolExe
        $PSCmdlet.ThrowTerminatingError($record)
    }

    try {
        $resolvedInstaller = (Resolve-Path -LiteralPath $InstallerPath -ErrorAction Stop).Path
    }
    catch {
        $record = New-IntuneDropPackagingErrorRecord -Message "Installer not found: $($_.Exception.Message)" -TargetObject $InstallerPath
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $leafName = [System.IO.Path]::GetFileName($resolvedInstaller)
    $stagingRootFull = [System.IO.Path]::GetFullPath($StagingPath)
    if (-not (Test-Path -LiteralPath $stagingRootFull)) {
        try {
            New-Item -ItemType Directory -Path $stagingRootFull -Force -ErrorAction Stop | Out-Null
        }
        catch {
            $record = New-IntuneDropPackagingErrorRecord -Message "Could not create staging root '$stagingRootFull': $($_.Exception.Message)" -TargetObject $StagingPath
            $PSCmdlet.ThrowTerminatingError($record)
        }
    }

    $jobSegment = [Guid]::NewGuid().ToString('n')
    $jobRoot = [System.IO.Path]::GetFullPath((Join-Path -Path $stagingRootFull -ChildPath $jobSegment))
    $inputDir = Join-Path -Path $jobRoot -ChildPath 'input'
    $outputDir = Join-Path -Path $jobRoot -ChildPath 'output'
    $stdoutPath = Join-Path -Path $jobRoot -ChildPath 'IntuneWinAppUtil.stdout.log'
    $stderrPath = Join-Path -Path $jobRoot -ChildPath 'IntuneWinAppUtil.stderr.log'

    try {
        New-Item -ItemType Directory -Path $inputDir, $outputDir -Force | Out-Null
    }
    catch {
        $record = New-IntuneDropPackagingErrorRecord -Message "Could not create staging directories under '$jobRoot': $($_.Exception.Message)" -TargetObject $jobRoot
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $stagedInstaller = Join-Path -Path $inputDir -ChildPath $leafName
    try {
        Copy-Item -LiteralPath $resolvedInstaller -Destination $stagedInstaller -Force -ErrorAction Stop
    }
    catch {
        $record = New-IntuneDropPackagingErrorRecord -Message "Could not copy installer into staging: $($_.Exception.Message)" -TargetObject $resolvedInstaller
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $argumentList = @(
        '-c', $inputDir
        '-s', $leafName
        '-o', $outputDir
    )

    $exitCode = $null
    try {
        $exitCode = Invoke-IntuneDropIntuneWinAppUtilProcess `
            -PrepToolExe $PrepToolExe `
            -ArgumentList $argumentList `
            -StandardOutputPath $stdoutPath `
            -StandardErrorPath $stderrPath
    }
    catch {
        $record = New-IntuneDropPackagingErrorRecord -Message "Failed to start prep tool: $($_.Exception.Message). See '$stderrPath'." -TargetObject $PrepToolExe
        $PSCmdlet.ThrowTerminatingError($record)
    }

    if ($exitCode -ne 0) {
        $stderrTail = $null
        if (Test-Path -LiteralPath $stderrPath) {
            try {
                $stderrTail = (Get-Content -LiteralPath $stderrPath -Raw -ErrorAction Stop).Trim()
                if ($stderrTail.Length -gt 2000) {
                    $stderrTail = $stderrTail.Substring(0, 2000) + '...'
                }
            }
            catch {
                $stderrTail = '(could not read stderr log)'
            }
        }

        $detail = "IntuneWinAppUtil.exe exited with code $exitCode. Stderr: $stderrTail"
        $record = New-IntuneDropPackagingErrorRecord -Message $detail -TargetObject $jobRoot
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $intunewinFiles = Get-ChildItem -LiteralPath $outputDir -Filter '*.intunewin' -File -ErrorAction Stop
    if ($intunewinFiles.Count -eq 0) {
        $record = New-IntuneDropPackagingErrorRecord -Message "Prep tool reported success but no .intunewin file was found under '$outputDir'. See '$stdoutPath' and '$stderrPath'." -TargetObject $outputDir
        $PSCmdlet.ThrowTerminatingError($record)
    }
    if ($intunewinFiles.Count -gt 1) {
        $record = New-IntuneDropPackagingErrorRecord -Message "Multiple .intunewin files found under '$outputDir'; expected exactly one." -TargetObject $outputDir
        $PSCmdlet.ThrowTerminatingError($record)
    }

    [pscustomobject]@{
        PSTypeName       = 'IntuneDrop.IntuneWinPackage'
        IntuneWinPath    = $intunewinFiles[0].FullName
        JobRoot          = $jobRoot
        InputDirectory   = $inputDir
        OutputDirectory  = $outputDir
        StdOutLog        = $stdoutPath
        StdErrLog        = $stderrPath
        StagedInstaller  = $stagedInstaller
    }
}

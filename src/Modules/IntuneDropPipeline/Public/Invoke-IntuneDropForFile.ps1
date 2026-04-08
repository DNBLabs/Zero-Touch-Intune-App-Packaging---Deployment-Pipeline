<#
.SYNOPSIS
    End-to-end processing for one installer: validate, pack, publish to Intune, assign, and move the file to done/ or failed/.
.DESCRIPTION
    Loads configuration, parses the filename, resolves MSI product code on Windows when needed, builds IntuneWin content, ensures a Graph session (unless -NoAutoConnect), creates the Win32 LOB app, uploads committed content, assigns the test group, then moves the original installer to done/. Any terminating error after configuration is loaded moves the installer to failed/ with a .reason.txt sidecar when possible.
.PARAMETER LiteralPath
    Full path to the .msi or .exe in the inbox (or any folder).
.PARAMETER SkipAssignment
    Skips New-IntuneDropWin32LobGroupAssignment (for experiments).
.PARAMETER NoAutoConnect
    Does not call Connect-IntuneDropGraphSession; requires an existing Connect-MgGraph application context.
.PARAMETER PassThru
    Emits a result object on success.
#>
function Invoke-IntuneDropForFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $LiteralPath,

        [Parameter()]
        [switch] $SkipAssignment,

        [Parameter()]
        [switch] $NoAutoConnect,

        [Parameter()]
        [switch] $PassThru
    )

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        throw "Installer not found or not a file: '$LiteralPath'"
    }

    $resolvedInstaller = (Resolve-Path -LiteralPath $LiteralPath).Path
    $configuration = $null

    try {
        $configuration = Get-IntuneDropConfiguration

        Write-IntuneDropLog -Level Info -Message ("Start processing '{0}'." -f $resolvedInstaller)

        $package = Get-IntuneDropPackageFromFileName -FileName $resolvedInstaller
        Write-IntuneDropLog -Level Info -Message ("Parsed package {0} {1} {2}." -f $package.Vendor, $package.AppName, $package.Version) -RuleId 'PARSE_OK'

        $productCode = $null
        if ($package.Extension -eq 'msi') {
            $productCode = Get-IntuneDropMsiProductCode -Path $resolvedInstaller
            Write-IntuneDropLog -Level Info -Message 'MSI ProductCode read for detection/uninstall.' -RuleId 'MSI_METADATA_OK'
        }

        $installIntent = Get-IntuneDropInstallIntent -Package $package -ProductCode $productCode
        Write-IntuneDropLog -Level Info -Message ("Allowlist intent {0}." -f $installIntent.AllowlistEntryId) -RuleId 'ALLOWLIST_OK'

        $packageResult = New-IntuneDropWin32Package `
            -InstallerPath $resolvedInstaller `
            -StagingPath $configuration.StagingPath `
            -PrepToolExe $configuration.PrepToolExe

        Write-IntuneDropLog -Level Info -Message ("Packaged to '{0}'." -f $packageResult.IntuneWinPath) -RuleId 'PACK_OK'

        if (-not $NoAutoConnect) {
            $existingContext = Get-IntuneDropMgContext
            if ($null -eq $existingContext) {
                Connect-IntuneDropGraphSession -UseConfiguration
            }
        }
        else {
            if ($null -eq (Get-IntuneDropMgContext)) {
                throw 'NoAutoConnect was specified but there is no active Microsoft Graph session. Run Connect-IntuneDropGraphSession first.'
            }
        }

        $createdApp = New-IntuneDropWin32LobApp -InstallIntent $installIntent -IntuneWinPath $packageResult.IntuneWinPath
        Write-IntuneDropLog -Level Info -Message ("Graph app created id {0}." -f $createdApp.Id) -RuleId 'GRAPH_APP_OK'

        $null = Publish-IntuneDropWin32LobIntuneWinContent -MobileAppId $createdApp.Id -IntuneWinPath $packageResult.IntuneWinPath
        Write-IntuneDropLog -Level Info -Message 'IntuneWin content committed in Graph.' -RuleId 'GRAPH_CONTENT_OK'

        if (-not $SkipAssignment) {
            $null = New-IntuneDropWin32LobGroupAssignment -MobileAppId $createdApp.Id -GroupId $configuration.TestGroupId
            Write-IntuneDropLog -Level Info -Message ("Assigned to group {0}." -f $configuration.TestGroupId) -RuleId 'GRAPH_ASSIGN_OK'
        }

        $donePath = Move-IntuneDropInstallerToOutcomeFolder -SourcePath $resolvedInstaller -DestinationDirectory $configuration.DonePath
        Write-IntuneDropLog -Level Info -Message ("Moved installer to '{0}'." -f $donePath) -RuleId 'DONE'

        if ($PassThru) {
            [pscustomobject]@{
                PSTypeName     = 'IntuneDrop.PipelineResult'
                Success        = $true
                MobileAppId    = $createdApp.Id
                IntuneWinPath  = $packageResult.IntuneWinPath
                InstallerMoved = $donePath
            }
        }
    }
    catch {
        $failureReason = $_.Exception.Message
        if ($null -ne $_.ErrorRecord.Exception) {
            $failureReason = $_.ErrorRecord.Exception.Message
        }

        Write-IntuneDropLog -Level Error -Message $failureReason -RuleId 'PIPELINE_FAILED'

        if ($null -ne $configuration) {
            try {
                if (Test-Path -LiteralPath $resolvedInstaller -PathType Leaf) {
                    $failedDestination = Move-IntuneDropInstallerToOutcomeFolder `
                        -SourcePath $resolvedInstaller `
                        -DestinationDirectory $configuration.FailedPath `
                        -FailureReason $failureReason
                    Write-IntuneDropLog -Level Warning -Message ("Moved failed installer to '{0}'." -f $failedDestination) -RuleId 'FAILED_MOVED'
                }
            }
            catch {
                Write-IntuneDropLog -Level Error -Message ("Could not move failed installer: {0}" -f $_.Exception.Message) -RuleId 'FAILED_MOVE_ERR'
            }
        }

        throw
    }
}

<#
.SYNOPSIS
    Builds the JSON-ready hashtable for POST /deviceAppManagement/mobileApps (win32LobApp).
#>
function ConvertTo-IntuneDropWin32LobCreateBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object] $InstallIntent,

        [Parameter(Mandatory)]
        [object] $IntuneWinMetadata,

        [Parameter(Mandatory)]
        [string] $IntuneWinFileName,

        [Parameter(Mandatory)]
        [long] $IntuneWinFileLengthBytes
    )

    $detectionRules = [System.Collections.ArrayList]::new()
    $detection = $InstallIntent.Detection
    if ($null -ne $detection) {
        switch ([string]$detection.RuleType) {
            'msiProductCode' {
                if ([string]::IsNullOrWhiteSpace([string]$detection.ProductCode)) {
                    $record = New-IntuneDropGraphErrorRecord -Message 'MSI detection requires ProductCode before creating the Win32 app in Graph.'
                    $PSCmdlet.ThrowTerminatingError($record)
                }
                [void]$detectionRules.Add(@{
                    '@odata.type'            = '#microsoft.graph.win32LobAppProductCodeRule'
                    'ruleType'               = 'detection'
                    'productCode'            = [string]$detection.ProductCode
                    'productVersionOperator' = 'notConfigured'
                    'productVersion'         = ''
                })
            }
            'file' {
                $fullPath = [string]$detection.Path
                $parent = Split-Path -Path $fullPath -Parent
                $leaf = Split-Path -Path $fullPath -Leaf
                # Graph v1.0 win32LobAppFileSystemOperationType includes version but not appVersion (beta adds appVersion, etc.). Create uses v1.0 in New-IntuneDropWin32LobApp.
                [void]$detectionRules.Add(@{
                    '@odata.type'          = '#microsoft.graph.win32LobAppFileSystemRule'
                    'ruleType'             = 'detection'
                    'path'                 = $parent
                    'fileOrFolderName'     = $leaf
                    'check32BitOn64System' = $false
                    'operationType'        = [string]$detection.DetectionType
                    'operator'             = [string]$detection.Operator
                    'comparisonValue'      = [string]$detection.ExpectedValue
                })
            }
            Default {
                $record = New-IntuneDropGraphErrorRecord -Message "Unsupported detection rule type '$($detection.RuleType)' for Graph body conversion."
                $PSCmdlet.ThrowTerminatingError($record)
            }
        }
    }

    if ($detectionRules.Count -eq 0) {
        $record = New-IntuneDropGraphErrorRecord -Message 'At least one detection rule is required before creating the Win32 app in Graph.'
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $sizeValue = $IntuneWinMetadata.UnencryptedContentSize
    if ($null -eq $sizeValue) {
        $sizeValue = $IntuneWinFileLengthBytes
    }

    $msiBlock = $null
    if (($InstallIntent.Package.Extension -eq 'msi') -and $null -ne $InstallIntent.Detection -and ($InstallIntent.Detection.RuleType -eq 'msiProductCode')) {
        $msiBlock = @{
            '@odata.type'    = '#microsoft.graph.win32LobAppMsiInformation'
            'packageType'    = 'perMachine'
            'productCode'    = [string]$InstallIntent.Detection.ProductCode
            'requiresReboot' = $false
        }
    }

    $body = [ordered]@{
        '@odata.type'                    = '#microsoft.graph.win32LobApp'
        'displayName'                    = [string]$InstallIntent.DisplayName
        'description'                    = 'Packaged via IntuneDropPipeline'
        'publisher'                      = [string]$InstallIntent.Package.Vendor
        'developer'                      = [string]$InstallIntent.Package.Vendor
        'owner'                          = [string]$InstallIntent.Package.Vendor
        'displayVersion'                 = [string]$InstallIntent.Package.Version
        'fileName'                       = $IntuneWinFileName
        'setupFilePath'                  = [string]$IntuneWinMetadata.SetupFileName
        # Do not set mobileLobApp.size on create (read-only in Graph); upload sets size on mobileAppContentFile. Still 400 when size was included after x64/x64 fix.
        'installCommandLine'             = [string]$InstallIntent.InstallCommandLine
        'uninstallCommandLine'           = [string]$InstallIntent.UninstallCommandLine
        # Match Microsoft Graph win32LobApp create examples (matching x64/x64 or x86/x86); explicit applicable none with allowed x64 produced 400 from Intune.
        'applicableArchitectures'        = 'x64'
        'allowedArchitectures'           = 'x64'
        # Graph expects values like Windows10_22H2 / Windows11_23H2 — a bare release label (e.g. 22H2) is rejected by the service.
        'minimumSupportedWindowsRelease' = 'Windows10_22H2'
        'rules'                         = @($detectionRules.ToArray())
        # v1.0 installExperience: only runAsAccount and deviceRestartBehavior (see Graph docs). maxRunTimeInMinutes is beta-only and broke v1.0 POST in captured payloads.
        'installExperience'             = @{
            '@odata.type'           = '#microsoft.graph.win32LobAppInstallExperience'
            'runAsAccount'          = 'system'
            'deviceRestartBehavior' = 'suppress'
        }
        'returnCodes'                   = @(
            @{ '@odata.type' = '#microsoft.graph.win32LobAppReturnCode'; 'returnCode' = 0; 'type' = 'success' }
            @{ '@odata.type' = '#microsoft.graph.win32LobAppReturnCode'; 'returnCode' = 1707; 'type' = 'softReboot' }
            @{ '@odata.type' = '#microsoft.graph.win32LobAppReturnCode'; 'returnCode' = 3010; 'type' = 'softReboot' }
            @{ '@odata.type' = '#microsoft.graph.win32LobAppReturnCode'; 'returnCode' = 1641; 'type' = 'hardReboot' }
            @{ '@odata.type' = '#microsoft.graph.win32LobAppReturnCode'; 'returnCode' = 1618; 'type' = 'retry' }
        )
    }

    if ($null -ne $msiBlock) {
        $body['msiInformation'] = $msiBlock
    }

    # #region agent log
    try {
        $dbgRepoRoot = Get-IntuneDropRepositoryRoot
        $dbgPath = Join-Path -Path $dbgRepoRoot -ChildPath 'debug-7596d3.log'
        $dbgRule0 = $body['rules'][0]
        $dbgData = [ordered]@{
            displayNameLen        = ($body['displayName']).Length
            extension             = [string]$InstallIntent.Package.Extension
            setupFilePath         = [string]$body['setupFilePath']
            fileName              = [string]$body['fileName']
            createBodyOmitsSize   = -not ($body.Keys -contains 'size')
            unencryptedSizeOrFile = [long]$sizeValue
            minWinRelease         = [string]$body['minimumSupportedWindowsRelease']
            applicableArch        = [string]$body['applicableArchitectures']
            allowedArch           = [string]$body['allowedArchitectures']
            rule0OdataType        = [string]$dbgRule0['@odata.type']
            rule0Path             = if ($null -ne $dbgRule0['path']) { [string]$dbgRule0['path'] } else { $null }
            rule0PathEmpty        = [string]::IsNullOrEmpty([string]$dbgRule0['path'])
            rule0FileOrFolderName = if ($null -ne $dbgRule0['fileOrFolderName']) { [string]$dbgRule0['fileOrFolderName'] } else { $null }
            rule0OperationType    = if ($null -ne $dbgRule0['operationType']) { [string]$dbgRule0['operationType'] } else { $null }
            hasMsiInformation     = $body.Keys -contains 'msiInformation'
            installCmdLen         = ($body['installCommandLine']).Length
            uninstallCmdLen       = ($body['uninstallCommandLine']).Length
            installExpKeys        = @([string[]]@($body['installExperience'].Keys))
        }
        $dbgPayload = [ordered]@{
            sessionId    = '7596d3'
            timestamp    = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
            hypothesisId = 'H1,H3,H4,H6,H10,H11'
            location     = 'ConvertTo-IntuneDropWin32LobCreateBody:end'
            message      = 'win32LobApp create body summary'
            data         = $dbgData
        }
        Add-Content -LiteralPath $dbgPath -Value ($dbgPayload | ConvertTo-Json -Compress -Depth 8) -Encoding utf8
    }
    catch { }
    # #endregion

    return [hashtable]$body
}

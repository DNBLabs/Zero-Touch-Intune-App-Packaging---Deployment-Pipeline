<#
.SYNOPSIS
    Watches the configured inbox with a debounced FileSystemWatcher and runs Invoke-IntuneDropInboxSweep after changes settle.
.DESCRIPTION
    Loads configuration, watches the inbox folder for Created, Changed, and Renamed events, and waits for a quiet period (debounce) before scanning. Runs one inbox sweep at startup unless -NoInitialSweep is set. For large installers, copy to a temporary name in the inbox first, then rename to the final Vendor_AppName_x.y.z.exe name so the watcher sees a complete file.
.PARAMETER DebounceSeconds
    Minimum time with no new filesystem signals before running a sweep. Reduces duplicate processing while files are still copying.
.PARAMETER NoInitialSweep
    If set, skips the first sweep when the watcher starts (only reacts to new drops).
#>
[CmdletBinding()]
param(
    [int] $DebounceSeconds = 3,

    [switch] $NoInitialSweep
)

$ErrorActionPreference = 'Stop'

$moduleRoot = $PSScriptRoot
$manifestPath = Join-Path -Path $moduleRoot -ChildPath 'Modules\IntuneDropPipeline\IntuneDropPipeline.psd1'

Import-Module -Name $manifestPath -Force

$configuration = Get-IntuneDropConfiguration
$inboxPath = [System.IO.Path]::GetFullPath($configuration.InboxPath)

$null = New-Item -ItemType Directory -Path $inboxPath -Force -ErrorAction SilentlyContinue

$watcher = New-Object System.IO.FileSystemWatcher -ArgumentList @(
    $inboxPath,
    '*.*'
)
$watcher.NotifyFilter = [System.IO.NotifyFilters]::FileName -bor [System.IO.NotifyFilters]::LastWrite
$watcher.IncludeSubdirectories = $false

$signalState = [hashtable]::Synchronized(@{
    LastSignalUtc = $null
})

$eventAction = {
    $Event.MessageData.LastSignalUtc = [datetime]::UtcNow
}

foreach ($eventName in @('Created', 'Changed', 'Renamed')) {
    $null = Register-ObjectEvent -InputObject $watcher -EventName $eventName -SourceIdentifier "IntuneDropInbox_$eventName" -Action $eventAction -MessageData $signalState
}

Write-Warning -Message 'Watch-Inbox.ps1 runs until you press Ctrl+C or end the session. Close large copies with a final rename into the inbox (see README).'

try {
    if (-not $NoInitialSweep) {
        Invoke-IntuneDropInboxSweep
    }

    $watcher.EnableRaisingEvents = $true
    $debounce = [TimeSpan]::FromSeconds($DebounceSeconds)

    while ($true) {
        Start-Sleep -Milliseconds 250
        if ($null -ne $signalState.LastSignalUtc) {
            $elapsed = [datetime]::UtcNow - $signalState.LastSignalUtc
            if ($elapsed -ge $debounce) {
                $signalState.LastSignalUtc = $null
                try {
                    Invoke-IntuneDropInboxSweep
                }
                catch {
                    Write-Error -ErrorRecord $PSItem
                }
            }
        }
    }
}
finally {
    $watcher.EnableRaisingEvents = $false
    foreach ($eventName in @('Created', 'Changed', 'Renamed')) {
        Unregister-Event -SourceIdentifier "IntuneDropInbox_$eventName" -ErrorAction SilentlyContinue
    }
    $watcher.Dispose()
    Write-Information -MessageData 'IntuneDrop inbox watch exited.' -InformationAction Continue
}

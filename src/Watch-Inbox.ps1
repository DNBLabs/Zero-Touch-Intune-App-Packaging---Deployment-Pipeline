<#
.SYNOPSIS
    Periodically runs Process-Inbox.ps1 to pick up new drops (simple polling watch).
.DESCRIPTION
    Intended for demo laptops: forever loop calling Process-Inbox with a sleep between passes. Prefer Task Scheduler invoking Process-Inbox.ps1 on a cadence for production-style hosts.
.PARAMETER PollIntervalSeconds
    Delay between inbox scans.
#>
[CmdletBinding()]
param(
    [int] $PollIntervalSeconds = 5
)

Write-Warning -Message 'Watch-Inbox.ps1 runs until you press Ctrl+C or end the session.'

$processScript = Join-Path -Path $PSScriptRoot -ChildPath 'Process-Inbox.ps1'

try {
    while ($true) {
        & $processScript -Once
        Start-Sleep -Seconds $PollIntervalSeconds
    }
}
finally {
    Write-Information -MessageData 'IntuneDrop watch loop exited.' -InformationAction Continue
}

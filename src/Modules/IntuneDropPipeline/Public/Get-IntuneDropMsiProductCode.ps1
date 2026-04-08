<#
.SYNOPSIS
    Reads the Windows Installer ProductCode property from an .msi database using the WindowsInstaller COM class.
.DESCRIPTION
    Requires Windows (Win32 Content Prep and typical Intune packaging targets Windows admins). Returns the braced product GUID string. Surfaces ERR_MSI_METADATA for missing files, non-MSI paths, unreadable databases, or non-Windows hosts.
.PARAMETER Path
    Absolute or relative path to an .msi file.
.OUTPUTS
    System.String containing the MSI ProductCode (for example {XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}).
.EXAMPLE
    Get-IntuneDropMsiProductCode -Path '.\inbox\Contoso_App_1.0.0.msi'
#>
function Get-IntuneDropMsiProductCode {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not $IsWindows) {
        $record = New-IntuneDropMsiMetadataErrorRecord -Message 'Reading MSI metadata requires Windows (Windows Installer COM is not available on this OS).' -TargetObject $Path
        $PSCmdlet.ThrowTerminatingError($record)
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $record = New-IntuneDropMsiMetadataErrorRecord -Message 'The path is empty.' -TargetObject $Path
        $PSCmdlet.ThrowTerminatingError($record)
    }

    try {
        $resolvedPath = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    }
    catch {
        $record = New-IntuneDropMsiMetadataErrorRecord -Message "Could not resolve path: $($_.Exception.Message)" -TargetObject $Path
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $extension = [System.IO.Path]::GetExtension($resolvedPath)
    if (-not $extension.Equals('.msi', [System.StringComparison]::OrdinalIgnoreCase)) {
        $record = New-IntuneDropMsiMetadataErrorRecord -Message "File must have extension '.msi'; got '$extension'." -TargetObject $resolvedPath
        $PSCmdlet.ThrowTerminatingError($record)
    }

    $comInstaller = $null
    $comDatabase = $null
    $comView = $null
    $comRecord = $null

    try {
        try {
            $comInstaller = New-Object -ComObject WindowsInstaller.Installer
            $comDatabase = $comInstaller.OpenDatabase($resolvedPath, 0)
            $comView = $comDatabase.OpenView("SELECT Value FROM Property WHERE Property='ProductCode'")
            $comView.Execute()
            $comRecord = $comView.Fetch()
        }
        catch {
            $record = New-IntuneDropMsiMetadataErrorRecord -Message "Windows Installer failed to open or query the database: $($_.Exception.Message)" -TargetObject $resolvedPath
            $PSCmdlet.ThrowTerminatingError($record)
        }

        if ($null -eq $comRecord) {
            $record = New-IntuneDropMsiMetadataErrorRecord -Message 'Property query returned no ProductCode row.' -TargetObject $resolvedPath
            $PSCmdlet.ThrowTerminatingError($record)
        }

        $productCode = $comRecord.StringData(1)
        if ([string]::IsNullOrWhiteSpace($productCode)) {
            $record = New-IntuneDropMsiMetadataErrorRecord -Message 'ProductCode property was empty.' -TargetObject $resolvedPath
            $PSCmdlet.ThrowTerminatingError($record)
        }

        return $productCode.Trim()
    }
    finally {
        if ($null -ne $comRecord) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($comRecord)
        }
        if ($null -ne $comView) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($comView)
        }
        if ($null -ne $comDatabase) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($comDatabase)
        }
        if ($null -ne $comInstaller) {
            [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($comInstaller)
        }
    }
}

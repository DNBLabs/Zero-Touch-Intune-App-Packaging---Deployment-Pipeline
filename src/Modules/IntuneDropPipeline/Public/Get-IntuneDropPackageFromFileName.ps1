<#
.SYNOPSIS
    Parses an installer file name against the strict Vendor_AppName_x.y.z.msi|exe convention.
.DESCRIPTION
    Vendor and app segments must not contain underscores. Version is two to four numeric segments (for example 1.2 or 1.2.3.4). Extension must be msi or exe (case insensitive). Accepts a full path and uses only the leaf file name.
.PARAMETER FileName
    File name or path to validate and parse.
.INPUTS
    System.String. You can pipe file names into this cmdlet.
.OUTPUTS
    System.Management.Automation.PSCustomObject with Vendor, AppName, Version, Extension, and FileName (leaf only).

.EXAMPLE
    Get-IntuneDropPackageFromFileName -FileName 'Contoso_DemoApp_1.0.0.msi'
#>
function Get-IntuneDropPackageFromFileName {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowEmptyString()]
        [string] $FileName
    )

    process {
        if ($null -eq $FileName) {
            $record = New-IntuneDropFilenameErrorRecord -Message 'The file name cannot be null.' -TargetObject $FileName
            $PSCmdlet.ThrowTerminatingError($record)
        }

        $leafName = [System.IO.Path]::GetFileName($FileName.Trim())
        if ([string]::IsNullOrWhiteSpace($leafName)) {
            $record = New-IntuneDropFilenameErrorRecord -Message 'The file name is empty or whitespace only.' -TargetObject $FileName
            $PSCmdlet.ThrowTerminatingError($record)
        }

        # Vendor and AppName: no underscores; version: 2–4 numeric segments; extension: msi|exe
        $pattern = '^(?<Vendor>[^_]+)_(?<AppName>[^_]+)_(?<Version>\d+(?:\.\d+){1,3})\.(?<Ext>msi|exe)$'
        if ($leafName -notmatch $pattern) {
            $detail = "Name '{0}' does not match Vendor_AppName_x.y.z.msi|exe (no underscores inside vendor or app segments)." -f $leafName
            $record = New-IntuneDropFilenameErrorRecord -Message $detail -TargetObject $leafName
            $PSCmdlet.ThrowTerminatingError($record)
        }

        [pscustomobject]@{
            PSTypeName = 'IntuneDrop.PackageFromFileName'
            FileName   = $leafName
            Vendor     = $Matches.Vendor
            AppName    = $Matches.AppName
            Version    = $Matches.Version
            Extension  = $Matches.Ext.ToLowerInvariant()
        }
    }
}

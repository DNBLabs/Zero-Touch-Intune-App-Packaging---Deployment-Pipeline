<#
.SYNOPSIS
    Converts the allowlist detection block into a plain custom object with templates expanded where applicable.
.PARAMETER Detection
    The nested detection object from an allowlist entry (may be null).
.PARAMETER Package
    Parsed package for token expansion in path/value templates.
.PARAMETER ProductCode
    Optional MSI product code when rule type requires it.
#>
function ConvertTo-IntuneDropDetectionSpec {
    [CmdletBinding()]
    param(
        [Parameter()]
        $Detection,

        [Parameter(Mandatory)]
        [object] $Package,

        [Parameter()]
        [string] $ProductCode
    )

    if ($null -eq $Detection) {
        return $null
    }

    $ruleType = [string]$Detection.ruleType
    $spec = [ordered]@{
        RuleType = $ruleType
    }

    switch ($ruleType.ToLowerInvariant()) {
        'msiproductcode' {
            $spec['Notes'] = [string]$Detection.notes
            $spec['ProductCode'] = if ([string]::IsNullOrWhiteSpace($ProductCode)) { $null } else { $ProductCode }
        }
        'file' {
            $spec['Path'] = Expand-IntuneDropTemplate -Template ([string]$Detection.pathTemplate) -Package $Package -ProductCode $ProductCode
            $spec['DetectionType'] = [string]$Detection.detectionType
            $spec['Operator'] = [string]$Detection.operator
            $spec['ExpectedValue'] = Expand-IntuneDropTemplate -Template ([string]$Detection.valueTemplate) -Package $Package -ProductCode $ProductCode
        }
        Default {
            $spec['Raw'] = $Detection
        }
    }

    return [pscustomobject]$spec
}

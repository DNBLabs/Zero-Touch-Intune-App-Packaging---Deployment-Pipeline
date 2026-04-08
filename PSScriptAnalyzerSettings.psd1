# PSScriptAnalyzer settings for this repository.
# PSAvoidUsingConvertToSecureStringWithPlainText: excluded because Connect-MgGraph ClientSecretCredential requires a
# SecureString built from the app secret read only from process environment (Get-IntuneDropConfiguration).

@{
    Severity            = @('Error', 'Warning')
    IncludeDefaultRules = $true
    ExcludeRules        = @(
        'PSAvoidUsingConvertToSecureStringWithPlainText'
    )
}

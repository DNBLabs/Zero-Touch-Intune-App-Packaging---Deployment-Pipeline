<#
.SYNOPSIS
    Offline tests for Graph-facing commands using mocked Invoke-IntuneDropGraphRequest.
#>
BeforeAll {
    $repoRoot = Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')
    $moduleManifest = Join-Path -Path $repoRoot -ChildPath 'src\Modules\IntuneDropPipeline\IntuneDropPipeline.psd1'
    Import-Module -Name $moduleManifest -Force

    function script:New-IntuneDropTestIntuneWinFile {
        param([Parameter(Mandatory)][string] $Path)
        $xml = @'
<ApplicationInfo>
  <Name>InsideSetup.msi</Name>
  <UnencryptedContentSize>2048</UnencryptedContentSize>
  <EncryptionInfo>
    <EncryptionKey>ZW5j</EncryptionKey>
    <MacKey>bWFj</MacKey>
    <InitializationVector>aXY=</InitializationVector>
    <Mac>a2V5</Mac>
    <ProfileIdentifier>cHJm</ProfileIdentifier>
    <FileDigest>ZGln</FileDigest>
    <FileDigestAlgorithm>SHA256</FileDigestAlgorithm>
  </EncryptionInfo>
</ApplicationInfo>
'@
        $utf8 = [System.Text.Encoding]::UTF8.GetBytes($xml)
        $stream = [System.IO.File]::Create($Path)
        try {
            $stream.Write([System.BitConverter]::GetBytes([int]$utf8.Length), 0, 4)
            $stream.Write($utf8, 0, $utf8.Length)
            $stream.Write((New-Object byte[] 16), 0, 16)
        }
        finally {
            $stream.Dispose()
        }
    }
}

AfterAll {
    Remove-Module -Name IntuneDropPipeline -Force -ErrorAction SilentlyContinue
}

Describe 'New-IntuneDropWin32LobApp (mocked Graph)' {
    It 'POSTs a win32LobApp and returns the new id' {
        Mock -ModuleName IntuneDropPipeline -CommandName Invoke-IntuneDropGraphRequest -MockWith {
            return @{ id = '11111111-2222-3333-4444-555555555555' }
        }

        $intunewinPath = Join-Path -Path $TestDrive -ChildPath 'drop.intunewin'
        New-IntuneDropTestIntuneWinFile -Path $intunewinPath

        $package = Get-IntuneDropPackageFromFileName -FileName 'Contoso_App_1.0.0.msi'
        $intent = Get-IntuneDropInstallIntent -Package $package -ProductCode '{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}'

        $created = New-IntuneDropWin32LobApp -InstallIntent $intent -IntuneWinPath $intunewinPath
        $created.Id | Should -Be '11111111-2222-3333-4444-555555555555'
    }
}

Describe 'New-IntuneDropWin32LobGroupAssignment (mocked Graph)' {
    It 'POSTs a group assignment with installIntent required (not requiredInstall)' {
        $script:groupAssignmentBody = $null
        Mock -ModuleName IntuneDropPipeline -CommandName Invoke-IntuneDropGraphRequest -MockWith {
            param([string] $Method, [string] $Uri, $Body)
            if ($Method -eq 'POST' -and $Uri -match '/assignments$') {
                $script:groupAssignmentBody = $Body
            }
            return @{ id = 'assignment-1' }
        }

        $result = New-IntuneDropWin32LobGroupAssignment -MobileAppId 'app-1' -GroupId 'group-2'
        $result.id | Should -Be 'assignment-1'
        $script:groupAssignmentBody | Should -Not -BeNullOrEmpty
        $script:groupAssignmentBody['@odata.type'] | Should -Be '#microsoft.graph.mobileAppAssignment'
        $script:groupAssignmentBody['intent'] | Should -Be 'required'
        $script:groupAssignmentBody['target']['@odata.type'] | Should -Be '#microsoft.graph.groupAssignmentTarget'
    }
}

Describe 'Publish-IntuneDropWin32LobIntuneWinContent (mocked Graph)' {
    BeforeEach {
        $script:publishGetCount = 0
    }

    It 'runs upload, commit, and patch when Graph and blob calls succeed' {
        Mock -ModuleName IntuneDropPipeline -CommandName Invoke-IntuneDropAzureBlobSinglePut -MockWith { }

        Mock -ModuleName IntuneDropPipeline -CommandName Invoke-IntuneDropGraphRequest -MockWith {
            param([string] $Method, [string] $Uri)

            if ($Method -eq 'POST' -and $Uri -match '/files$') {
                return @{ id = 'file-9' }
            }
            if ($Method -eq 'POST' -and $Uri -match 'contentVersions$') {
                return @{ id = 'ver-9' }
            }
            if ($Method -eq 'GET' -and $Uri -match '/files/file-9$') {
                $script:publishGetCount++
                switch ($script:publishGetCount) {
                    1 {
                        return @{ azureStorageUri = 'https://127.0.0.1/fake?sas=1'; isCommitted = $false }
                    }
                    2 {
                        return @{ isCommitted = $false; uploadState = 'commitFilePending' }
                    }
                    Default {
                        return @{ isCommitted = $true; uploadState = 'commitFileSuccess' }
                    }
                }
            }
            if ($Method -eq 'POST' -and $Uri -match 'commit') {
                return @{ }
            }
            if ($Method -eq 'PATCH') {
                return @{ }
            }

            throw "Unexpected Graph call $Method $Uri"
        }

        $intunewinPath = Join-Path -Path $TestDrive -ChildPath 'upload.intunewin'
        New-IntuneDropTestIntuneWinFile -Path $intunewinPath

        $publish = Publish-IntuneDropWin32LobIntuneWinContent -MobileAppId 'app-publish-1' -IntuneWinPath $intunewinPath `
            -AzureUriPollSeconds 0 -CommitPollSeconds 0 `
            -AzureUriMaxAttempts 5 -CommitMaxAttempts 5

        $publish.MobileAppId | Should -Be 'app-publish-1'
        $publish.CommittedContentVersion | Should -Be 'ver-9'
        $publish.ContentFileId | Should -Be 'file-9'
    }
}

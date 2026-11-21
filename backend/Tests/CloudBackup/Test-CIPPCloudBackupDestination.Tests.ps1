BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Set-CIPPCloudBackupObject { param($Destination, $Key, $Body, $ContentType, $Metadata) }
    function Get-CIPPCloudBackupObject { param($Destination, $Key) }
    function Remove-CIPPCloudBackupObject { param($Destination, $Key, $VersionId) }
    function Get-CIPPCloudBackupObjectVersionList { param($Destination, $Prefix) }
    function Get-CIPPCloudBackupRetentionRule { param($Destination, $RuleName) }
    function Get-CIPPCloudBackupVersioning { param($Destination) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup/Test-CIPPCloudBackupDestination.ps1')
    $script:Destination = [pscustomobject]@{ Provider = 'AzureBlob' }
}

Describe 'Test-CIPPCloudBackupDestination' {
    BeforeEach {
        $script:Written = $null
        Mock Set-CIPPCloudBackupObject { $script:Written = @{ Key = $Key; Body = $Body } }
        Mock Get-CIPPCloudBackupObject { @{ Body = $script:Written.Body; Metadata = @{} } }
        Mock Remove-CIPPCloudBackupObject { }
        Mock Get-CIPPCloudBackupRetentionRule { $null }
        Mock Get-CIPPCloudBackupVersioning { 'Enabled' }
        Mock Get-CIPPCloudBackupObjectVersionList {
            [pscustomobject]@{ Key = $Prefix; VersionId = 'v1'; IsLatest = $false }
            [pscustomobject]@{ Key = $Prefix; VersionId = 'v2'; IsLatest = $false }
            [pscustomobject]@{ Key = "$Prefix-other"; VersionId = 'v9'; IsLatest = $true }
        }
    }

    It 'passes when every check works and probes with one .cipp-test object' {
        $Result = Test-CIPPCloudBackupDestination -Destination $Destination
        $Result.Write | Should -BeTrue
        $Result.Read | Should -BeTrue
        $Result.Delete | Should -BeTrue
        $Result.Lifecycle | Should -BeTrue
        $Result.Versioning | Should -Be 'Enabled'
        $Result.Passed | Should -BeTrue
        $Result.ContentReady | Should -BeTrue
        $Result.Errors.Count | Should -Be 0
        $Written.Key | Should -Match '^\.cipp-test-[0-9a-f-]{36}$'
        Should -Invoke Get-CIPPCloudBackupObject -ParameterFilter { $Key -eq $script:Written.Key }
        Should -Invoke Remove-CIPPCloudBackupObject -ParameterFilter { $Key -eq $script:Written.Key }
    }

    It 'skips read and delete when the write fails' {
        Mock Set-CIPPCloudBackupObject { throw 'Azure Storage returned 403 (AuthorizationPermissionMismatch): denied' }
        $Result = Test-CIPPCloudBackupDestination -Destination $Destination
        $Result.Write | Should -BeFalse
        $Result.Read | Should -BeFalse
        $Result.Delete | Should -BeFalse
        $Result.Lifecycle | Should -BeTrue
        $Result.Passed | Should -BeFalse
        $Result.Errors | Should -Be @('Write: Azure Storage returned 403 (AuthorizationPermissionMismatch): denied')
        Should -Invoke Get-CIPPCloudBackupObject -Times 0 -Exactly
        Should -Invoke Remove-CIPPCloudBackupObject -Times 0 -Exactly
    }

    It 'fails the read when the object comes back different' {
        Mock Get-CIPPCloudBackupObject { @{ Body = [byte[]](1, 2); Metadata = @{} } }
        $Result = Test-CIPPCloudBackupDestination -Destination $Destination
        $Result.Read | Should -BeFalse
        $Result.Delete | Should -BeTrue
        $Result.Passed | Should -BeFalse
        $Result.Errors[0] | Should -BeLike 'Read:*'
    }

    It 'still deletes the probe when the read throws' {
        Mock Get-CIPPCloudBackupObject { throw 'read denied' }
        $Result = Test-CIPPCloudBackupDestination -Destination $Destination
        $Result.Delete | Should -BeTrue
        $Result.Errors | Should -Be @('Read: read denied')
    }

    It 'reports a delete failure' {
        Mock Remove-CIPPCloudBackupObject { throw 'delete denied' }
        $Result = Test-CIPPCloudBackupDestination -Destination $Destination
        $Result.Delete | Should -BeFalse
        $Result.Passed | Should -BeFalse
        $Result.Errors | Should -Be @('Delete: delete denied')
    }

    It 'fails when the lifecycle configuration cannot be read' {
        Mock Get-CIPPCloudBackupRetentionRule { throw 'Azure Resource Manager returned AuthorizationFailed: no' }
        $Result = Test-CIPPCloudBackupDestination -Destination $Destination
        $Result.Lifecycle | Should -BeFalse
        $Result.Passed | Should -BeFalse
        $Result.Errors | Should -Be @('Lifecycle: Azure Resource Manager returned AuthorizationFailed: no')
    }

    It 'records a versioning failure without failing the test' {
        Mock Get-CIPPCloudBackupVersioning { throw 'versioning denied' }
        $Result = Test-CIPPCloudBackupDestination -Destination $Destination
        $Result.Versioning | Should -Be 'Unknown'
        $Result.Passed | Should -BeTrue
        $Result.Errors | Should -Be @('Versioning: versioning denied')
    }

    It 'reports ContentReady <Expected> for versioning <Versioning> without changing Passed' -ForEach @(
        @{ Versioning = 'Suspended'; Expected = $false }
        @{ Versioning = 'Disabled'; Expected = $false }
    ) {
        Mock Get-CIPPCloudBackupVersioning { $Versioning }
        $Result = Test-CIPPCloudBackupDestination -Destination $Destination
        $Result.Passed | Should -BeTrue
        $Result.ContentReady | Should -Be $Expected
    }

    It 'is not ContentReady when a check fails even with versioning enabled' {
        Mock Get-CIPPCloudBackupRetentionRule { throw 'denied' }
        $Result = Test-CIPPCloudBackupDestination -Destination $Destination
        $Result.Versioning | Should -Be 'Enabled'
        $Result.ContentReady | Should -BeFalse
    }

    It 'returns one result object when the upload returns its version' {
        Mock Set-CIPPCloudBackupObject { $script:Written = @{ Key = $Key; Body = $Body }; [pscustomobject]@{ Key = $Key; Bytes = $Body.Length; VersionId = 'v1' } }
        @(Test-CIPPCloudBackupDestination -Destination $Destination).Count | Should -Be 1
    }

    It 'deletes the probe versions on Azure and reports VersionDelete' {
        $Result = Test-CIPPCloudBackupDestination -Destination $Destination
        $Result.VersionDelete | Should -BeTrue
        $Result.ContentReady | Should -BeTrue
        Should -Invoke Get-CIPPCloudBackupObjectVersionList -Times 1 -Exactly -ParameterFilter { $Prefix -eq $script:Written.Key }
        Should -Invoke Remove-CIPPCloudBackupObject -Times 1 -Exactly -ParameterFilter { $VersionId -eq 'v1' -and $Key -eq $script:Written.Key }
        Should -Invoke Remove-CIPPCloudBackupObject -Times 1 -Exactly -ParameterFilter { $VersionId -eq 'v2' }
        Should -Invoke Remove-CIPPCloudBackupObject -Times 0 -Exactly -ParameterFilter { $VersionId -eq 'v9' }
    }

    It 'is not ContentReady when Azure refuses version deletes, without failing Passed' {
        Mock Remove-CIPPCloudBackupObject { throw "Azure Storage refused to delete version v1 of 'k' (AuthorizationPermissionMismatch): CIPP's app needs the Storage Blob Data Owner role on the storage account to remove old versions." } -ParameterFilter { $VersionId }
        $Result = Test-CIPPCloudBackupDestination -Destination $Destination
        $Result.Delete | Should -BeTrue
        $Result.VersionDelete | Should -BeFalse
        $Result.Passed | Should -BeTrue
        $Result.ContentReady | Should -BeFalse
        $Result.Errors[0] | Should -BeLike 'Version delete:*Storage Blob Data Owner*'
    }

    It 'counts a version delete refused only by immutability as VersionDelete' {
        Mock Remove-CIPPCloudBackupObject {
            $Exception = [System.Management.Automation.RuntimeException]::new('Azure Storage returned 409 (BlobImmutableDueToPolicy): immutable')
            $Exception.Data['ErrorCode'] = 'BlobImmutableDueToPolicy'
            throw $Exception
        } -ParameterFilter { $VersionId }
        $Result = Test-CIPPCloudBackupDestination -Destination $Destination
        $Result.VersionDelete | Should -BeTrue
        $Result.ContentReady | Should -BeTrue
        $Result.Errors.Count | Should -Be 0
    }

    It 'does not delete S3 versions and follows Delete for VersionDelete' {
        $Result = Test-CIPPCloudBackupDestination -Destination ([pscustomobject]@{ Provider = 'S3' })
        $Result.VersionDelete | Should -BeTrue
        $Result.ContentReady | Should -BeTrue
        Should -Invoke Get-CIPPCloudBackupObjectVersionList -Times 0 -Exactly
        Should -Invoke Remove-CIPPCloudBackupObject -Times 0 -Exactly -ParameterFilter { $VersionId }

        Mock Remove-CIPPCloudBackupObject { throw 'denied' }
        (Test-CIPPCloudBackupDestination -Destination ([pscustomobject]@{ Provider = 'S3' })).VersionDelete | Should -BeFalse
    }
}

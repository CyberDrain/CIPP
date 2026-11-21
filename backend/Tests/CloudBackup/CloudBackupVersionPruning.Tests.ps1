BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup'
    function Get-CIPPClientCredentialToken { param($TenantId, $ClientId, $ClientSecret, $Scope) }
    foreach ($Name in 'Invoke-CIPPCloudBackupAzureBlobRequest', 'Remove-CIPPCloudBackupAzureObject', 'Remove-CIPPCloudBackupAzureExpiredVersion', 'Remove-CIPPCloudBackupExpiredVersion', 'Get-CIPPCloudBackupAzureObjectVersionList') {
        . (Join-Path $Folder "$Name.ps1")
    }

    $script:Destination = [pscustomobject]@{ Provider = 'AzureBlob'; StorageAccount = 'cippbackup'; Container = 'backups'; AzureTenantId = 't'; ClientId = 'c'; Secret = 's' }

    function Get-VersionId {
        param([double]$DaysAgo)
        [datetime]::UtcNow.AddDays(-$DaysAgo).ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', [cultureinfo]::InvariantCulture)
    }

    function New-Version {
        param([string]$Name, [double]$DaysAgo, [switch]$Current, [switch]$Marker)
        $Id = Get-VersionId $DaysAgo
        $Meta = if ($Marker) { "<Metadata><cippdeletedat>$Id</cippdeletedat></Metadata>" } else { '<Metadata />' }
        $IsCurrent = if ($Current) { '<IsCurrentVersion>true</IsCurrentVersion>' } else { '' }
        [pscustomobject]@{ Id = $Id; Xml = "<Blob><Name>$Name</Name><VersionId>$Id</VersionId>$IsCurrent<Properties><Last-Modified>Fri, 20 Nov 2026 10:00:00 GMT</Last-Modified><Content-Length>1</Content-Length></Properties>$Meta</Blob>" }
    }

    function Set-Pages {
        param([object[][]]$Pages)
        $script:Pages = $Pages
        $script:Deletes = [System.Collections.Generic.List[string]]::new()
        Mock Invoke-CIPPCloudBackupAzureBlobRequest {
            $Index = if ($Query.marker) { [int]$Query.marker } else { 0 }
            $Next = if ($Index + 1 -lt $script:Pages.Count) { "<NextMarker>$($Index + 1)</NextMarker>" } else { '<NextMarker />' }
            $Xml = "<?xml version=`"1.0`" encoding=`"utf-8`"?><EnumerationResults><Blobs>$(($script:Pages[$Index] | ForEach-Object Xml) -join '')</Blobs>$Next</EnumerationResults>"
            @{ StatusCode = 200; Headers = @{}; Body = [System.Text.Encoding]::UTF8.GetBytes($Xml) }
        } -ParameterFilter { $Method -eq 'GET' }
        Mock Invoke-CIPPCloudBackupAzureBlobRequest {
            $script:Deletes.Add("$Key@$($Query.versionid)")
            @{ StatusCode = 202; Headers = @{}; Body = [byte[]]::new(0) }
        } -ParameterFilter { $Method -eq 'DELETE' }
    }
}

Describe 'Remove-CIPPCloudBackupExpiredVersion on Azure' {
    It 'keeps the old version of an item that stayed unchanged for a long time and was edited today' {
        $Old = New-Version 'p/a' 400
        Set-Pages @(, @($Old, (New-Version 'p/a' 0.01 -Current)))
        $Result = Remove-CIPPCloudBackupExpiredVersion -Destination $Destination -Prefix 'p/' -Days 90
        $Result.Examined | Should -Be 2
        $Result.Deleted | Should -Be 0
        $Deletes.Count | Should -Be 0
    }

    It 'deletes a version replaced 100 days ago with 90 days of retention, never the current version' {
        $Old = New-Version 'p/a' 200
        $New = New-Version 'p/a' 100 -Current
        Set-Pages @(, @($Old, $New))
        $Result = Remove-CIPPCloudBackupExpiredVersion -Destination $Destination -Prefix 'p/' -Days 90
        $Result.Deleted | Should -Be 1
        $Deletes | Should -Be @("p/a@$($Old.Id)")
        Should -Invoke Invoke-CIPPCloudBackupAzureBlobRequest -ParameterFilter { $Method -eq 'GET' -and $Query.include -eq 'versions,metadata' -and $Query.prefix -eq 'p/' }
    }

    It 'ages a deleted blob from its deletion marker: <Name>' -ForEach @(
        @{ Name = 'deleted 100 days ago'; DeletedDaysAgo = 100; Expected = 2 }
        @{ Name = 'deleted 10 days ago'; DeletedDaysAgo = 10; Expected = 0 }
    ) {
        $Old = New-Version 'p/gone' 300
        $DeleteMarker = New-Version 'p/gone' $DeletedDaysAgo -Marker
        Set-Pages @(, @($Old, $DeleteMarker))
        (Remove-CIPPCloudBackupExpiredVersion -Destination $Destination -Prefix 'p/' -Days 90).Deleted | Should -Be $Expected
        if ($Expected) { $Deletes | Should -Be @("p/gone@$($Old.Id)", "p/gone@$($DeleteMarker.Id)") }
    }

    It 'keeps the last version of a blob deleted without a marker' {
        Set-Pages @(, @((New-Version 'p/x' 500)))
        (Remove-CIPPCloudBackupExpiredVersion -Destination $Destination -Prefix 'p/' -Days 90).Deleted | Should -Be 0
    }

    It 'joins a blob whose versions continue on the next page before deciding' {
        $V1 = New-Version 'p/a' 200
        $V2 = New-Version 'p/a' 150
        $V3 = New-Version 'p/a' 100 -Current
        Set-Pages @(@($V1, $V2), @($V3, (New-Version 'p/b' 1 -Current)))
        $Result = Remove-CIPPCloudBackupExpiredVersion -Destination $Destination -Prefix 'p/' -Days 90
        $Result.Examined | Should -Be 4
        $Deletes | Should -Be @("p/a@$($V1.Id)", "p/a@$($V2.Id)")
        Should -Invoke Invoke-CIPPCloudBackupAzureBlobRequest -Times 2 -Exactly -ParameterFilter { $Method -eq 'GET' }
    }

    It 'orders versions by id even when the listing does not' {
        $V1 = New-Version 'p/a' 200
        $V2 = New-Version 'p/a' 100 -Current
        Set-Pages @(, @($V2, $V1))
        $null = Remove-CIPPCloudBackupExpiredVersion -Destination $Destination -Prefix 'p/' -Days 90
        $Deletes | Should -Be @("p/a@$($V1.Id)")
    }

    It 'stops at -MaxDeletes and leaves the rest for the next call' {
        $Page = foreach ($Letter in 'a', 'b', 'c', 'd', 'e') { New-Version "p/$Letter" 200; New-Version "p/$Letter" 100 -Current }
        Set-Pages @(, @($Page))
        $Result = Remove-CIPPCloudBackupExpiredVersion -Destination $Destination -Prefix 'p/' -Days 90 -MaxDeletes 2
        $Result.Deleted | Should -Be 2
        $Deletes.Count | Should -Be 2
        $Deletes[0] | Should -BeLike 'p/a@*'
        $Deletes[1] | Should -BeLike 'p/b@*'
    }

    It 'stops with an error naming the Storage Blob Data Owner role when version deletes are refused' {
        $Page = foreach ($Letter in 'a', 'b') { New-Version "p/$Letter" 200; New-Version "p/$Letter" 100 -Current }
        Set-Pages @(, @($Page))
        Mock Invoke-CIPPCloudBackupAzureBlobRequest { @{ StatusCode = 403; Headers = @{}; Body = [byte[]]::new(0); ErrorCode = 'AuthorizationPermissionMismatch' } } -ParameterFilter { $Method -eq 'DELETE' }
        $Result = Remove-CIPPCloudBackupExpiredVersion -Destination $Destination -Prefix 'p/' -Days 90
        $Result.Deleted | Should -Be 0
        $Result.Failed | Should -Be 1
        $Result.Errors[0] | Should -BeLike '*AuthorizationPermissionMismatch*Storage Blob Data Owner*'
        Should -Invoke Invoke-CIPPCloudBackupAzureBlobRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'skips versions still under immutability without failing and goes on with the next blob' {
        $A1 = New-Version 'p/a' 200
        $A2 = New-Version 'p/a' 150
        $A3 = New-Version 'p/a' 100 -Current
        $B1 = New-Version 'p/b' 200
        $B2 = New-Version 'p/b' 100 -Current
        Set-Pages @(, @($A1, $A2, $A3, $B1, $B2))
        Mock Invoke-CIPPCloudBackupAzureBlobRequest {
            $script:Deletes.Add("$Key@$($Query.versionid)")
            if ($Key -eq 'p/a') {
                $Exception = [System.Management.Automation.RuntimeException]::new('Azure Storage returned 409 (BlobImmutableDueToPolicy): This operation is not permitted as the blob is immutable due to a policy.')
                $Exception.Data['StatusCode'] = 409
                $Exception.Data['ErrorCode'] = 'BlobImmutableDueToPolicy'
                throw $Exception
            }
            @{ StatusCode = 202; Headers = @{}; Body = [byte[]]::new(0) }
        } -ParameterFilter { $Method -eq 'DELETE' }

        $Result = Remove-CIPPCloudBackupExpiredVersion -Destination $Destination -Prefix 'p/' -Days 90

        $Result.Skipped | Should -Be 1
        $Result.Failed | Should -Be 0
        $Result.Deleted | Should -Be 1
        $Result.Errors.Count | Should -Be 0
        $Deletes | Should -Be @("p/a@$($A1.Id)", "p/b@$($B1.Id)")
    }

    It 'still counts other conflicts as failures' {
        Set-Pages @(, @((New-Version 'p/a' 200), (New-Version 'p/a' 100 -Current)))
        Mock Invoke-CIPPCloudBackupAzureBlobRequest {
            $Exception = [System.Management.Automation.RuntimeException]::new('Azure Storage returned 409 (LeaseIdMissing): leased')
            $Exception.Data['ErrorCode'] = 'LeaseIdMissing'
            throw $Exception
        } -ParameterFilter { $Method -eq 'DELETE' }
        $Result = Remove-CIPPCloudBackupExpiredVersion -Destination $Destination -Prefix 'p/' -Days 90
        $Result.Failed | Should -Be 1
        $Result.Skipped | Should -Be 0
    }

    It 'treats a version that is already gone as deleted' {
        Set-Pages @(, @((New-Version 'p/a' 200), (New-Version 'p/a' 100 -Current)))
        Mock Invoke-CIPPCloudBackupAzureBlobRequest { @{ StatusCode = 404; Headers = @{}; Body = [byte[]]::new(0); ErrorCode = 'BlobNotFound' } } -ParameterFilter { $Method -eq 'DELETE' }
        (Remove-CIPPCloudBackupExpiredVersion -Destination $Destination -Prefix 'p/' -Days 90).Deleted | Should -Be 1
    }
}

Describe 'Remove-CIPPCloudBackupExpiredVersion on S3' {
    It 'leaves pruning to the lifecycle rule without calling S3' {
        function Invoke-CIPPS3Request { throw 'should not be called' }
        $Result = Remove-CIPPCloudBackupExpiredVersion -Destination ([pscustomobject]@{ Provider = 'S3' }) -Prefix 'p/' -Days 90
        $Result.Examined | Should -Be 0
        $Result.Deleted | Should -Be 0
    }
}

Describe 'Azure deletes and delete markers' {
    BeforeEach {
        $script:Requests = [System.Collections.Generic.List[object]]::new()
        Mock Invoke-CIPPCloudBackupAzureBlobRequest {
            $script:Requests.Add([pscustomobject]@{ Method = $Method; Query = $Query; Headers = $Headers })
            @{ StatusCode = 202; Headers = @{}; Body = [byte[]]::new(0) }
        }
    }

    It 'records the deletion time as a metadata version before deleting' {
        Remove-CIPPCloudBackupAzureObject -Destination $Destination -Key 'p/a'
        $Requests.Count | Should -Be 2
        $Requests[0].Method | Should -Be 'PUT'
        $Requests[0].Query.comp | Should -Be 'metadata'
        [datetime]::Parse($Requests[0].Headers['x-ms-meta-cippdeletedat']).ToUniversalTime() | Should -BeGreaterThan ([datetime]::UtcNow.AddMinutes(-1))
        $Requests[1].Method | Should -Be 'DELETE'
        $Requests[1].Query | Should -BeNullOrEmpty
    }

    It 'does nothing for a blob that was never written' {
        Mock Invoke-CIPPCloudBackupAzureBlobRequest { $script:Requests.Add($Method); @{ StatusCode = 404; Headers = @{}; Body = [byte[]]::new(0); ErrorCode = 'BlobNotFound' } }
        { Remove-CIPPCloudBackupAzureObject -Destination $Destination -Key 'never' } | Should -Not -Throw
        $Requests | Should -Be @('PUT')
    }

    It 'deletes one version by id without the snapshot header' {
        Remove-CIPPCloudBackupAzureObject -Destination $Destination -Key 'p/a' -VersionId 'v1'
        $Requests.Count | Should -Be 1
        $Requests[0].Method | Should -Be 'DELETE'
        $Requests[0].Query.versionid | Should -Be 'v1'
        $Requests[0].Headers | Should -BeNullOrEmpty
    }

    It 'lists a marker version as a delete marker' {
        $Old = New-Version 'p/gone' 30
        $DeleteMarker = New-Version 'p/gone' 1 -Marker
        Set-Pages @(, @($Old, $DeleteMarker))
        $Versions = @(Get-CIPPCloudBackupAzureObjectVersionList -Destination $Destination -Prefix 'p/')
        $Versions.IsDeleteMarker | Should -Be @($false, $true)
        $Versions.IsLatest | Should -Be @($false, $false)
    }
}

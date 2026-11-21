BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    function Get-CIPPCloudBackupJobContext { param($Job) }
    function Save-CIPPCloudBackupJobManifest { param($Context, [string[]]$Keys, [string[]]$Paths) }
    function Invoke-CIPPCloudBackupExport { param($Context) }
    function Get-CIPPCloudBackupObjectList { param($Destination, $Prefix) }
    function Get-CIPPCloudBackupObjectVersionList { param($Destination, $Prefix) }
    function Remove-CIPPCloudBackupObject { [CmdletBinding(SupportsShouldProcess = $true)] param($Destination, $Key, $VersionId) }

    $script:JobId = 'aaaaaaaa-0000-0000-0000-000000000001'
    function New-JobRow {
        param($Status = 'Queued', $ManifestReady = $false)
        [pscustomobject]@{
            PartitionKey = 'CloudBackupJob'; RowKey = $script:JobId; Type = 'Export'; Status = $Status; PolicyId = 'p1'; Workload = 'teams'; SourceTenantId = 'c1'; SourceTenant = 'contoso.com'
            SourceOwnerName = 'Team One'; RequestedBy = 'admin@partner.com'; Parameters = '{"Keys":[],"Paths":[]}'; ManifestReady = $ManifestReady; ItemCount = 0; StartedAt = ''
            ExportKey = ''; ExportRemovedAt = ''
        }
    }
}

Describe 'Push-CloudBackupExport' {
    BeforeEach {
        $script:Job = New-JobRow
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPAzDataTableEntity { $script:Job } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add($Entity) } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Get-CIPPCloudBackupJobContext { [pscustomobject]@{ JobId = $script:JobId; TenantId = 'c1'; TenantFilter = 'contoso.com'; Workload = 'teams'; RunStamp = '20261101T000000Z' } }
        Mock Save-CIPPCloudBackupJobManifest { [pscustomobject]@{ Items = 12; Parts = 1 } }
        Mock Invoke-CIPPCloudBackupExport { [pscustomobject]@{ Key = "p1/exports/$($script:JobId).zip"; Bytes = 5000; Items = 11; Failed = 1; Warnings = @(foreach ($i in 1..60) { "w$i" }) } }
        Mock Write-LogMessage { }
    }

    It 'writes the manifest, builds the zip and records the download for 7 days' {
        Push-CloudBackupExport -Item @{ JobId = $script:JobId }

        Should -Invoke Save-CIPPCloudBackupJobManifest -Times 1 -Exactly
        Should -Invoke Invoke-CIPPCloudBackupExport -Times 1 -Exactly
        $Final = $script:Writes[-1]
        $Final.Status | Should -Be 'Completed'
        $Final.ExportKey | Should -Be "p1/exports/$($script:JobId).zip"
        $Final.ExportBytes | Should -Be 5000
        ([datetime]$Final.ExpiresAt).ToUniversalTime() | Should -BeGreaterThan ([datetime]::UtcNow.AddDays(6.9))
        @([CIPP.CippJson]::ConvertFromJson($Final.Warnings)).Count | Should -Be 50
        $Summary = [CIPP.CippJson]::ConvertFromJson($Final.Summary)
        $Summary.Items | Should -Be 12
        $Summary.Failed | Should -Be 1
        Should -Invoke Write-LogMessage -ParameterFilter { $API -eq 'CloudBackupRestore' -and $sev -eq 'Info' -and $message -like 'Export*started for admin@partner.com*Team One*' }
        Should -Invoke Write-LogMessage -ParameterFilter { $API -eq 'CloudBackupRestore' -and $sev -eq 'Warning' -and $message -like '*11 of 12 item(s) exported, 1 failed*' }
    }

    It 'marks the job failed when the export fails' {
        Mock Invoke-CIPPCloudBackupExport { throw 'storage down' }
        Push-CloudBackupExport -Item @{ JobId = $script:JobId }
        $script:Writes[-1].Status | Should -Be 'Failed'
        $script:Writes[-1].Error | Should -Be 'storage down'
    }

    It 'does nothing for a finished job' {
        $script:Job = New-JobRow -Status 'Failed'
        Push-CloudBackupExport -Item @{ JobId = $script:JobId }
        $script:Writes.Count | Should -Be 0
    }
}

Describe 'Push-CloudBackupJobCleanup' {
    BeforeEach {
        $script:Job = New-JobRow -Status 'Completed'
        $script:Job.ExportKey = "p1/exports/$($script:JobId).zip"
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:RemovedRows = $null
        $script:Deleted = [System.Collections.Generic.List[string]]::new()
        $script:Objects = @{
            "p1/exports/$($script:JobId).zip" = @([pscustomobject]@{ Key = "p1/exports/$($script:JobId).zip" })
            "p1/jobs/$($script:JobId)/"       = @([pscustomobject]@{ Key = "p1/jobs/$($script:JobId)/items/00000.jsonl.gz" }, [pscustomobject]@{ Key = "p1/jobs/$($script:JobId)/results/00000.jsonl.gz" })
        }
        Mock Get-CIPPAzDataTableEntity { $script:Job } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add($Entity) } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Remove-CIPPAzDataTableEntity { $script:RemovedRows = $Entity } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Get-CIPPCloudBackupPolicy { [pscustomobject]@{ Id = 'p1'; DestinationId = 'd1' } }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Provider = 'AzureBlob' } }
        Mock Get-CIPPCloudBackupObjectList { $script:Objects[$Prefix] }
        Mock Get-CIPPCloudBackupObjectVersionList { foreach ($Object in @($script:Objects[$Prefix])) { [pscustomobject]@{ Key = $Object.Key; VersionId = 'v1' }; [pscustomobject]@{ Key = $Object.Key; VersionId = 'v2' } } }
        Mock Remove-CIPPCloudBackupObject { $script:Deleted.Add("$Key@$VersionId") }
        Mock Write-LogMessage { }
    }

    It 'deletes an expired export with its versions and marks it removed' {
        Push-CloudBackupJobCleanup -Item @{ JobId = $script:JobId; Scope = 'Export' }

        @($script:Deleted) | Should -Be @("p1/exports/$($script:JobId).zip@", "p1/exports/$($script:JobId).zip@v1", "p1/exports/$($script:JobId).zip@v2")
        $script:Writes[-1].ExportRemovedAt | Should -Not -BeNullOrEmpty
        $script:RemovedRows | Should -BeNullOrEmpty
    }

    It 'deletes all job data and then the job record' {
        Push-CloudBackupJobCleanup -Item @{ JobId = $script:JobId; Scope = 'All' }

        $script:Deleted.Count | Should -Be 9
        @($script:RemovedRows.PartitionKey) | Should -Be @('CloudBackupJob', 'CloudBackupJobResult')
    }

    It 'removes the record and leaves versions it cannot delete to the retention' {
        Mock Remove-CIPPCloudBackupObject { if ($VersionId) { throw 'needs Storage Blob Data Owner' } else { $script:Deleted.Add($Key) } }

        Push-CloudBackupJobCleanup -Item @{ JobId = $script:JobId; Scope = 'All' }

        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' -and $message -like "*expire with the policy's retention*" }
        @($script:RemovedRows.PartitionKey) | Should -Be @('CloudBackupJob', 'CloudBackupJobResult')
    }

    It 'stops after its delete budget and leaves the rest for the next cleanup' {
        $script:Objects["p1/jobs/$($script:JobId)/"] = @(foreach ($i in 1..5001) { [pscustomobject]@{ Key = "p1/jobs/$($script:JobId)/results/$i" } })

        Push-CloudBackupJobCleanup -Item @{ JobId = $script:JobId; Scope = 'All' }

        $script:Deleted.Count | Should -Be 5000
        $script:RemovedRows | Should -BeNullOrEmpty
        $script:Writes[-1].CleanupQueuedAt | Should -Be ''
    }
}

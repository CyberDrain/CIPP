BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    function Get-CIPPCloudBackupJobContext { param($Job) }
    function Save-CIPPCloudBackupJobManifest { param($Context, [string[]]$Keys, [string[]]$Paths) }
    function Get-CIPPCloudBackupJsonl { param($Destination, $Key) }
    function Set-CIPPCloudBackupJsonl { param($Destination, $Key, [object[]]$Items, $KeyId, [byte[]]$EncryptionKey) }
    function Invoke-CIPPCloudBackupExchangeRestoreStep { param($Context, $State) }

    $script:JobId = 'aaaaaaaa-0000-0000-0000-000000000001'
    function New-JobRow {
        param($Type = 'RestorePreview', $Status = 'Queued', $State = '', $ResultCount = 0, $ManifestReady = $false, $Summary = '')
        [pscustomobject]@{
            PartitionKey = 'CloudBackupJob'; RowKey = $script:JobId; Type = $Type; Status = $Status; PolicyId = 'p1'; Workload = 'exchange'
            SourceTenantId = 'c1'; SourceOwnerName = 'User One'; RequestedBy = 'admin@partner.com'; Parameters = '{"Keys":["k1"],"Paths":["Inbox"]}'
            ManifestReady = $ManifestReady; ItemCount = 7; State = $State; ResultCount = $ResultCount; Summary = $Summary; StartedAt = ''
        }
    }
    function New-Result {
        param([int]$Index, $Status = 'Planned', $Action = 'Create')
        [pscustomobject]@{ Key = "k$Index"; Name = "Item $Index"; Path = 'Inbox'; Type = 'message'; Action = $Action; Status = $Status; Message = if ($Status -eq 'Failed') { 'denied' } else { '' }; TargetPath = 'Restored/Inbox' }
    }
}

Describe 'Push-CloudBackupRestore' {
    BeforeEach {
        $script:Job = New-JobRow
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Pages = [ordered]@{}
        $script:Steps = @()
        $script:StepStates = [System.Collections.Generic.List[object]]::new()
        $script:Context = [pscustomobject]@{
            JobId = $script:JobId; PolicyId = 'p1'; TenantId = 'c1'; TenantFilter = 'contoso.com'; Workload = 'exchange'; Apply = $false; KeyId = 'key-1'; Key = [byte[]]::new(32)
            Destination = [pscustomobject]@{ Provider = 'S3' }; RunStamp = '20261101T000000Z'; ConflictAction = 'Skip'; Location = 'RestoredFolder'
            Target = @{ OwnerId = 'u2'; OwnerType = 'User'; UserPrincipalName = 'two@contoso.com' }
        }
        Mock Get-CIPPAzDataTableEntity { $script:Job } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add($Entity) } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Get-CIPPCloudBackupJobContext { $script:Context }
        Mock Save-CIPPCloudBackupJobManifest { [pscustomobject]@{ Items = 7; Parts = 1 } }
        Mock Set-CIPPCloudBackupJsonl { $script:Pages[$Key] = @($Items) }
        Mock Get-CIPPCloudBackupJsonl { , @($script:Pages[$Key]) }
        Mock Invoke-CIPPCloudBackupExchangeRestoreStep {
            $script:StepStates.Add($State)
            $Index = [int]$State.Step
            $Step = $script:Steps[$Index]
            [pscustomobject]@{ State = @{ Step = $Index + 1 }; Done = $Index + 1 -ge $script:Steps.Count; Results = $Step; Bytes = 100 }
        }
        Mock Write-LogMessage { }
    }

    It 'writes the manifest, runs the steps until done and records results, summary and state after every step' {
        $script:Steps = @(
            , @((New-Result 1), (New-Result 2 -Action 'Skip' -Status 'Skipped'))
            , @()
            , @((New-Result 3 -Status 'Failed'), (New-Result 4 -Action 'NotRestorable' -Status 'Skipped'))
        )

        Push-CloudBackupRestore -Item @{ JobId = $script:JobId }

        Should -Invoke Save-CIPPCloudBackupJobManifest -Times 1 -Exactly -ParameterFilter { @($Keys) -contains 'k1' -and @($Paths) -contains 'Inbox' }
        $script:StepStates.Count | Should -Be 3
        $script:StepStates[0] | Should -BeNullOrEmpty
        $script:StepStates[2].Step | Should -Be 2
        @($script:Pages.Keys) | Should -Be @("p1/jobs/$($script:JobId)/results/00000.jsonl.gz.enc")
        @($script:Pages[0].Key) | Should -Be @('k1', 'k2', 'k3', 'k4')
        Should -Invoke Set-CIPPCloudBackupJsonl -Times 2 -Exactly -ParameterFilter { $KeyId -eq 'key-1' }

        $StepWrites = @($script:Writes).Where({ $_.ContainsKey('State') })
        $StepWrites.Count | Should -Be 3
        $StepWrites[2].ResultCount | Should -Be 4
        $StepWrites[2].ResultPages | Should -Be 1
        $Summary = [CIPP.CippJson]::ConvertFromJson($StepWrites[2].Summary)
        $Summary.Items | Should -Be 7
        $Summary.Processed | Should -Be 4
        $Summary.Create | Should -Be 2
        $Summary.Skip | Should -Be 1
        $Summary.NotRestorable | Should -Be 1
        $Summary.Failed | Should -Be 1
        $Summary.Planned | Should -Be 1
        $Summary.Bytes | Should -Be 300
        $script:Writes[-1].Status | Should -Be 'Completed'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like "*'Inbox/Item 3'*denied" }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Info' -and $message -like '*started for admin@partner.com*User One*two@contoso.com*' }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*completed:*Failed 1*' }
    }

    It 'starts a new results page every 1000 results' {
        $script:Steps = @(
            , @(foreach ($i in 1..600) { New-Result $i })
            , @(foreach ($i in 601..1200) { New-Result $i })
        )

        Push-CloudBackupRestore -Item @{ JobId = $script:JobId }

        @($script:Pages[0]).Count | Should -Be 1000
        @($script:Pages[1]).Count | Should -Be 200
        $script:Pages[1][0].Key | Should -Be 'k1001'
    }

    It 'resumes from the saved state, results page and summary without writing the manifest again' {
        $script:Job = New-JobRow -Status 'Running' -State '{"Step":1}' -ResultCount 1002 -ManifestReady $true -Summary '{"Items":7,"Processed":1002,"Create":1002,"Planned":1002,"Bytes":5}'
        $script:Pages["p1/jobs/$($script:JobId)/results/00001.jsonl.gz.enc"] = @((New-Result 1001), (New-Result 1002))
        $script:Steps = @(, @(); , @(New-Result 1003))

        Push-CloudBackupRestore -Item @{ JobId = $script:JobId }

        Should -Invoke Save-CIPPCloudBackupJobManifest -Times 0 -Exactly
        $script:StepStates.Count | Should -Be 1
        $script:StepStates[0].Step | Should -Be 1
        @($script:Pages["p1/jobs/$($script:JobId)/results/00001.jsonl.gz.enc"].Key) | Should -Be @('k1001', 'k1002', 'k1003')
        $Last = @($script:Writes).Where({ $_.ContainsKey('State') })[-1]
        $Last.ResultCount | Should -Be 1003
        ([CIPP.CippJson]::ConvertFromJson($Last.Summary)).Create | Should -Be 1003
        Should -Invoke Write-LogMessage -ParameterFilter { $message -like '*resumed*' }
    }

    It 'fails the job without retrying when the step refuses the target' {
        Mock Invoke-CIPPCloudBackupExchangeRestoreStep { throw [System.ArgumentException]::new('The target mailbox was not found') }

        Push-CloudBackupRestore -Item @{ JobId = $script:JobId }

        $script:Writes[-1].Status | Should -Be 'Failed'
        $script:Writes[-1].Error | Should -Be 'The target mailbox was not found'
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Error' -and $API -eq 'CloudBackupRestore' }
    }

    It 'does nothing for a finished job' {
        $script:Job = New-JobRow -Status 'Completed'
        Push-CloudBackupRestore -Item @{ JobId = $script:JobId }
        $script:Writes.Count | Should -Be 0
        Should -Invoke Invoke-CIPPCloudBackupExchangeRestoreStep -Times 0 -Exactly
    }
}

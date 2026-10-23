# Pester tests for Invoke-ListAuditLogFeedCycles - per-tick feed and processing times for the Feed Status page.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListAuditLogFeedCycles.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Test-CIPPAccess { param($Request, [switch]$TenantList) }
    function Get-CippTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Get-CippErrorStatusCode { param($ErrorRecord) 500 }

    . $FunctionPath

    function Invoke-Cycles { Invoke-ListAuditLogFeedCycles -Request ([pscustomobject]@{ Query = [pscustomobject]@{ Hours = 48 } }) -TriggerMetadata $null }
}

Describe 'Invoke-ListAuditLogFeedCycles' {

    BeforeEach {
        Mock Test-CIPPAccess { @('AllTenants') }
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'AuditLogFeedCycles' } {
            @(
                [pscustomobject]@{ CycleId = '202610241200'; StartedUtc = [datetime]'2026-10-24T12:00:00Z'; FinishedUtc = [datetime]'2026-10-24T12:00:30Z'; Tenants = 25; Feeds = 50; Failed = 1; Parked = 2; Blobs = 10; Records = 1000; Evaluated = 900; Stored = 5 }
                [pscustomobject]@{ CycleId = '202610241200'; StartedUtc = [datetime]'2026-10-24T12:00:05Z'; FinishedUtc = [datetime]'2026-10-24T12:00:40Z'; Tenants = 10; Feeds = 20; Failed = 0; Parked = 0; Blobs = 4; Records = 200; Evaluated = 150; Stored = 3 }
                [pscustomobject]@{ CycleId = '202610241215'; StartedUtc = [datetime]'2026-10-24T12:15:00Z'; FinishedUtc = [datetime]'2026-10-24T12:15:20Z'; Tenants = 35; Feeds = 70; Failed = 0; Parked = 2; Blobs = 0; Records = 0; Evaluated = 0; Stored = 0 }
            )
        }
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'AuditLogCoverage' } {
            @(
                [pscustomobject]@{ CycleId = '202610241200'; State = 'Processed'; MatchedCount = 3; ProcessedUtc = [datetime]'2026-10-24T12:01:00Z' }
                [pscustomobject]@{ CycleId = '202610241200'; State = 'Processed'; MatchedCount = 2; ProcessedUtc = [datetime]'2026-10-24T12:01:10Z' }
                [pscustomobject]@{ CycleId = $null; State = 'Processed'; MatchedCount = 9; ProcessedUtc = [datetime]'2026-10-24T12:01:10Z' }
            )
        }
    }

    It 'folds every task of a tick into one cycle, newest first, timed from the first start to the last processed window' {
        $Body = @((Invoke-Cycles).Body)
        $Body.CycleId | Should -Be @('202610241215', '202610241200')
        $Cycle = $Body[1]
        $Cycle.Tasks | Should -Be 2
        $Cycle.Tenants | Should -Be 35
        $Cycle.Records | Should -Be 1200
        $Cycle.Stored | Should -Be 8
        $Cycle.Failed | Should -Be 1
        $Cycle.FeedSeconds | Should -Be 40
        $Cycle.Windows | Should -Be 2
        $Cycle.Alerts | Should -Be 5
        $Cycle.ProcessingSeconds | Should -Be 30
    }

    It 'leaves processing time empty while a window of the cycle is still processing' {
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'AuditLogCoverage' } {
            @(
                [pscustomobject]@{ CycleId = '202610241200'; State = 'Processed'; MatchedCount = 3; ProcessedUtc = [datetime]'2026-10-24T12:01:00Z' }
                [pscustomobject]@{ CycleId = '202610241200'; State = 'Processing'; MatchedCount = $null; ProcessedUtc = $null }
            )
        }
        $Cycle = @((Invoke-Cycles).Body).Where({ $_.CycleId -eq '202610241200' })[0]
        $Cycle.WindowsProcessed | Should -Be 1
        $Cycle.ProcessingSeconds | Should -BeNullOrEmpty
    }

    It 'refuses a caller limited to some tenants' {
        Mock Test-CIPPAccess { @('tid-1') }
        (Invoke-Cycles).StatusCode | Should -Be 403
    }
}

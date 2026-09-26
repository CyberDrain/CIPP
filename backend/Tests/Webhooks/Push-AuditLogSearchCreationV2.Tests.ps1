# Pester tests for Push-AuditLogSearchCreationV2.
#
# These tests pin the existing ledger semantics before optimizing AuditLogCoverage reads.
# In particular, old Planned rows can still be due even when they fall outside the planner's
# normal 24-hour horizon, so a storage optimization must not silently drop retries/backlog.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Push-AuditLogSearchCreationV2.ps1'

    function Get-CippTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Get-CippAuditLogPlannedWindows { param($ExistingRows, $Now) }
    function Get-CippAuditLogReconciliationWindows { param($ExistingRows, $Now) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force, $OperationType) }
    function New-CippAuditLogSearchV2 { param($TenantFilter, $StartTime, $EndTime) }
    function Get-CippAuditLogNextAttempt { param($Attempts) }

    . $FunctionPath
}

Describe 'Push-AuditLogSearchCreationV2' {
    BeforeEach {
        $script:LedgerRows = @()
        $script:RegularOwed = @()
        $script:ReconOwed = @()
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:SearchCalls = [System.Collections.Generic.List[object]]::new()
        $script:SearchResults = [System.Collections.Generic.Queue[object]]::new()

        Mock Get-CippTable {
            param($TableName)
            @{ Context = "ctx:$TableName" }
        }

        $script:LedgerReadFilters = [System.Collections.Generic.List[string]]::new()
        $script:LedgerReadProperties = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPAzDataTableEntity {
            param($Context, $Filter, $Property)
            $script:LedgerReadFilters.Add([string]$Filter)
            $script:LedgerReadProperties.Add(@($Property))
            return @($script:LedgerRows | Where-Object {
                if (-not $Filter) { return $true }
                if ($Filter -match "RowKey ge '([^']+)' and RowKey lt '([^']+)'") {
                    $Lower = $Matches[1]
                    $Upper = $Matches[2]
                    $Key = [string]$_.RowKey
                    return ([string]::CompareOrdinal($Key, $Lower) -ge 0 -and [string]::CompareOrdinal($Key, $Upper) -lt 0)
                }
                return $true
            })
        }

        Mock Get-CippAuditLogPlannedWindows {
            param($ExistingRows, $Now)
            return $script:RegularOwed
        }

        Mock Get-CippAuditLogReconciliationWindows {
            param($ExistingRows, $Now)
            return $script:ReconOwed
        }

        Mock Add-CIPPAzDataTableEntity {
            param($Context, $Entity, [switch]$Force, $OperationType)
            $script:Writes.Add([pscustomobject]@{
                Context = $Context
                Entity = $Entity
                OperationType = $OperationType
                Force = [bool]$Force
            })
        }

        Mock New-CippAuditLogSearchV2 {
            param($TenantFilter, $StartTime, $EndTime)
            $script:SearchCalls.Add([pscustomobject]@{
                TenantFilter = $TenantFilter
                StartTime = $StartTime
                EndTime = $EndTime
            })
            if ($script:SearchResults.Count -gt 0) {
                return $script:SearchResults.Dequeue()
            }
            [pscustomobject]@{ Outcome = 'Created'; Id = 'search-default'; Status = 'succeeded'; Throttled = $false }
        }

        Mock Get-CippAuditLogNextAttempt {
            param($Attempts)
            [datetime]::UtcNow.AddMinutes(5)
        }
    }

    It 'uses indexed RowKey ranges instead of reading the full tenant partition' {
        $null = Push-AuditLogSearchCreationV2 -Item @{ TenantFilter = 'contoso.com'; TenantId = 'tenant-1' }

        $script:LedgerReadFilters | Should -Not -Contain "PartitionKey eq 'contoso.com'"
        ($script:LedgerReadFilters | Where-Object { $_ -match "RowKey ge '0' and RowKey lt ':'" }).Count | Should -Be 1
        ($script:LedgerReadFilters | Where-Object { $_ -eq "PartitionKey eq 'contoso.com' and RowKey ge 'RECON-' and RowKey lt 'RECON.'" }).Count | Should -Be 1
    }

    It 'projects only required fields while preserving LargeEntity metadata' {
        $null = Push-AuditLogSearchCreationV2 -Item @{ TenantFilter = 'contoso.com'; TenantId = 'tenant-1' }

        $script:LedgerReadProperties.Count | Should -Be 2
        $Expected = @(
            'PartitionKey', 'RowKey', 'WindowStart', 'WindowEnd', 'State', 'NextAttemptUtc',
            'Attempts', 'RetryCount', 'ThrottleCount',
            'OriginalEntityId', 'PartIndex', 'PartCount', 'SplitOverProps'
        )
        foreach ($Properties in $script:LedgerReadProperties) {
            @($Properties).Count | Should -Be $Expected.Count
            foreach ($Name in $Expected) {
                @($Properties) | Should -Contain $Name
            }
        }
    }

    It 'seeds and creates a newly owed regular window' {
        $script:RegularOwed = @(
            [pscustomobject]@{
                RowKey = '20260922120500'
                WindowStart = [datetime]'2026-09-22T12:05:00Z'
                WindowEnd = [datetime]'2026-09-22T12:40:00Z'
            }
        )

        Push-AuditLogSearchCreationV2 -Item @{ TenantFilter = 'contoso.com'; TenantId = 'tenant-1' } | Should -BeTrue
        $script:SearchCalls.Count | Should -Be 1
        ($script:Writes | Where-Object { $_.Entity.RowKey -eq '20260922120500' -and $_.Entity.State -eq 'Planned' }).Count | Should -Be 1
        ($script:Writes | Where-Object { $_.Entity.RowKey -eq '20260922120500' -and $_.Entity.State -eq 'Created' }).Count | Should -Be 1
    }

    It 'seeds and creates a reconciliation window' {
        $script:ReconOwed = @(
            [pscustomobject]@{
                RowKey = 'RECON-20260922000000'
                WindowStart = [datetime]'2026-09-22T00:00:00Z'
                WindowEnd = [datetime]'2026-09-22T12:00:00Z'
            }
        )

        $null = Push-AuditLogSearchCreationV2 -Item @{ TenantFilter = 'contoso.com'; TenantId = 'tenant-1' }
        $script:SearchCalls.Count | Should -Be 1
        ($script:Writes | Where-Object { $_.Entity.RowKey -eq 'RECON-20260922000000' -and $_.Entity.State -eq 'Planned' }).Count | Should -Be 1
    }

    It 'keeps an old due Planned row eligible even outside the planner horizon' {
        $script:LedgerRows = @(
            [pscustomobject]@{
                PartitionKey = 'contoso.com'
                RowKey = '20260919000500'
                WindowStart = [datetime]'2026-09-19T00:05:00Z'
                WindowEnd = [datetime]'2026-09-19T00:40:00Z'
                State = 'Planned'
                Attempts = 2
                RetryCount = 2
                ThrottleCount = 0
                NextAttemptUtc = [datetime]'2026-09-19T01:00:00Z'
            }
        )

        $null = Push-AuditLogSearchCreationV2 -Item @{ TenantFilter = 'contoso.com'; TenantId = 'tenant-1' }
        $script:SearchCalls.Count | Should -Be 1
        $script:SearchCalls[0].StartTime | Should -Be ([datetimeoffset]'2026-09-19T00:05:00Z').UtcDateTime
    }

    It 'does not retry a Planned row whose NextAttemptUtc is still in the future' {
        $script:LedgerRows = @(
            [pscustomobject]@{
                PartitionKey = 'contoso.com'
                RowKey = '20260922120500'
                WindowStart = [datetime]'2026-09-22T12:05:00Z'
                WindowEnd = [datetime]'2026-09-22T12:40:00Z'
                State = 'Planned'
                Attempts = 1
                RetryCount = 1
                ThrottleCount = 0
                NextAttemptUtc = [datetime]'2099-01-01T00:00:00Z'
            }
        )

        $null = Push-AuditLogSearchCreationV2 -Item @{ TenantFilter = 'contoso.com'; TenantId = 'tenant-1' }
        $script:SearchCalls.Count | Should -Be 0
    }

    It 'ignores manual rows when building the create batch' {
        $script:LedgerRows = @(
            [pscustomobject]@{
                PartitionKey = 'contoso.com'
                RowKey = 'MANUAL-20260922120000'
                WindowStart = [datetime]'2026-09-22T12:00:00Z'
                WindowEnd = [datetime]'2026-09-22T12:30:00Z'
                State = 'Created'
                Attempts = 0
                RetryCount = 0
                ThrottleCount = 0
            }
        )

        $null = Push-AuditLogSearchCreationV2 -Item @{ TenantFilter = 'contoso.com'; TenantId = 'tenant-1' }
        $script:SearchCalls.Count | Should -Be 0
    }

    It 'prioritizes the newest regular window before older backlog' {
        $script:LedgerRows = @(
            [pscustomobject]@{ PartitionKey='contoso.com'; RowKey='20260922000500'; WindowStart=[datetime]'2026-09-22T00:05:00Z'; WindowEnd=[datetime]'2026-09-22T00:40:00Z'; State='Planned'; Attempts=0; RetryCount=0; ThrottleCount=0 }
            [pscustomobject]@{ PartitionKey='contoso.com'; RowKey='RECON-20260922000000'; WindowStart=[datetime]'2026-09-22T00:00:00Z'; WindowEnd=[datetime]'2026-09-22T12:00:00Z'; State='Planned'; Attempts=0; RetryCount=0; ThrottleCount=0 }
            [pscustomobject]@{ PartitionKey='contoso.com'; RowKey='20260922120500'; WindowStart=[datetime]'2026-09-22T12:05:00Z'; WindowEnd=[datetime]'2026-09-22T12:40:00Z'; State='Planned'; Attempts=0; RetryCount=0; ThrottleCount=0 }
        )

        $null = Push-AuditLogSearchCreationV2 -Item @{ TenantFilter = 'contoso.com'; TenantId = 'tenant-1' }
        $script:SearchCalls.Count | Should -Be 3
        $script:SearchCalls[0].StartTime | Should -Be ([datetimeoffset]'2026-09-22T12:05:00Z').UtcDateTime
    }

    It 'stops creating searches after a 429 and defers remaining batch rows' {
        $script:LedgerRows = @(
            [pscustomobject]@{ PartitionKey='contoso.com'; RowKey='20260922120500'; WindowStart=[datetime]'2026-09-22T12:05:00Z'; WindowEnd=[datetime]'2026-09-22T12:40:00Z'; State='Planned'; Attempts=0; RetryCount=0; ThrottleCount=0 }
            [pscustomobject]@{ PartitionKey='contoso.com'; RowKey='20260922000500'; WindowStart=[datetime]'2026-09-22T00:05:00Z'; WindowEnd=[datetime]'2026-09-22T00:40:00Z'; State='Planned'; Attempts=0; RetryCount=0; ThrottleCount=0 }
        )
        $script:SearchResults.Enqueue([pscustomobject]@{
            Outcome = 'Throttled'; Id = $null; Status = '429'; Throttled = $true; Message = 'Too many searches'
        })

        $null = Push-AuditLogSearchCreationV2 -Item @{ TenantFilter = 'contoso.com'; TenantId = 'tenant-1' }
        $script:SearchCalls.Count | Should -Be 1
        ($script:Writes | Where-Object { $_.Entity.State -eq 'Planned' -and $_.OperationType -eq 'UpsertMerge' }).Count | Should -Be 2
    }
}

# A scheduled task whose command throws, or whose results cannot be stored, must be recorded as Failed (or
# Failed - Planned when it has a next run), not overwritten with Completed / Planned and a success log entry.
# A one-off task or a trigger that fires once must stay terminal after a failure, so it is not re-queued.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-ExecScheduledCommand.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Push-ExecScheduledCommand.ps1 under Modules/' }

    function Set-CippScheduledTaskContext { param($TaskId, $AlertReNotify, $AlertRun) }
    function Set-CippUserAgentContext { param($Headers, $Source, $TaskId) }
    function Get-CippTable { param($tablename) }
    function Get-AzDataTableEntity { param($Context, $Filter) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPSchedulerBlockedCommands { @() }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($headers, $API, $message, $sev, $tenant, $tenantid, $LogData) }
    function Get-DeltaQueryUrl { param($TenantFilter, $PartitionKey) }
    function New-GraphDeltaQuery { param($DeltaUrl, $TenantFilter, $PartitionKey) }
    function Test-DeltaQueryConditions { param($Query, $Trigger, $TenantFilter, $LastTrigger) }
    function Clear-CIPPImmutableID { param($UserID, $TenantFilter) }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPScheduledTaskNextRun.ps1')

    function New-TaskItem {
        param([string]$Recurrence = '0', [string]$ExecutionMode)
        $TaskInfo = [pscustomobject]@{
            PartitionKey  = 'ScheduledTask'
            RowKey        = 'task-1'
            Name          = 'Clear immutable ID'
            Command       = 'Clear-CIPPImmutableID'
            Tenant        = 'a.onmicrosoft.com'
            Recurrence    = $Recurrence
            ScheduledTime = [string]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - 60)
            TaskState     = 'Pending'
        }
        if ($ExecutionMode) {
            $Trigger = @{ Type = 'DeltaQuery'; ExecutePerResource = $true; ExecutionMode = $ExecutionMode }
            $TaskInfo | Add-Member -NotePropertyName Trigger -NotePropertyValue ($Trigger | ConvertTo-Json -Compress)
        }
        [pscustomobject]@{
            Command    = 'Clear-CIPPImmutableID'
            Parameters = @{ TenantFilter = 'a.onmicrosoft.com'; UserID = '%id%' }
            TaskInfo   = $TaskInfo
        }
    }
}

Describe 'Push-ExecScheduledCommand failure outcomes' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        Mock Set-CippScheduledTaskContext {}
        Mock Set-CippUserAgentContext {}
        Mock Get-CippTable { @{ Context = 'stub' } }
        Mock Get-AzDataTableEntity { [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; TaskState = 'Pending' } }
        Mock Update-AzDataTableEntity { $script:Writes.Add($Entity) }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'cust-a' } }
        Mock Get-CippException { @{ NormalizedError = $Exception.Exception.Message } }
        Mock Write-LogMessage {}
        Mock Get-DeltaQueryUrl { 'https://graph.example/delta' }
        Mock New-GraphDeltaQuery { @{ value = @() } }
        Mock Test-DeltaQueryConditions { @{ ConditionsMet = $true; MatchedData = @(@{ id = 'bad' }, @{ id = 'good' }) } }
        Mock Clear-CIPPImmutableID { 'Cleared' }
        Mock Get-Command -ParameterFilter { $Name -eq 'Clear-CIPPImmutableID' } -MockWith {
            [pscustomobject]@{ Module = 'CIPPCore'; Parameters = @{ TenantFilter = $null; UserID = $null } }
        }
    }

    It 'records a throwing task with recurrence "<Recurrence>" as <Expected>' -ForEach @(
        @{ Recurrence = '0'; Expected = 'Failed' }
        @{ Recurrence = ''; Expected = 'Failed' }
        @{ Recurrence = '15m'; Expected = 'Failed - Planned' }
    ) {
        Mock Clear-CIPPImmutableID { throw 'command failure' }

        $Result = Push-ExecScheduledCommand -Item (New-TaskItem -Recurrence $Recurrence)

        $Result | Should -Be 'Task Failed.'
        $script:Writes[-1].TaskState | Should -Be $Expected
        $script:Writes[-1].Results | Should -Match 'command failure'
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $message -like 'Successfully executed task*' }
    }

    It 'records a task whose results cannot be stored as <Expected> (recurrence "<Recurrence>", mode "<Mode>")' -ForEach @(
        @{ Recurrence = '0'; Mode = $null; Expected = 'Failed' }
        @{ Recurrence = ''; Mode = $null; Expected = 'Failed' }
        @{ Recurrence = '15m'; Mode = $null; Expected = 'Failed - Planned' }
        @{ Recurrence = '15m'; Mode = 'once'; Expected = 'Failed' }
    ) {
        # Results over 64000 characters go to the results table, which is unavailable here.
        Mock Clear-CIPPImmutableID { 'x' * 70000 }
        Mock Add-CIPPAzDataTableEntity { throw 'storage unavailable' }

        $Result = Push-ExecScheduledCommand -Item (New-TaskItem -Recurrence $Recurrence -ExecutionMode $Mode)

        $Result | Should -Be 'Task Failed.'
        $script:Writes[-1].TaskState | Should -Be $Expected
        $script:Writes[-1].Results | Should -Be 'storage unavailable'
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $message -like 'Successfully executed task*' }
    }

    It 'records a per-resource failure in a trigger task as Failed - Planned and keeps the other results' {
        Mock Clear-CIPPImmutableID { if ($UserID -eq 'bad') { throw 'resource failure' } 'Cleared good' }

        $Result = Push-ExecScheduledCommand -Item (New-TaskItem -Recurrence '15m' -ExecutionMode 'always')

        $Result | Should -Be 'Task Failed.'
        $script:Writes[-1].TaskState | Should -Be 'Failed - Planned'
        $script:Writes[-1].Results | Should -Match 'Task Failed: resource failure'
        $script:Writes[-1].Results | Should -Match 'Cleared good'
    }

    It 'still records a successful task as <Expected> with recurrence "<Recurrence>"' -ForEach @(
        @{ Recurrence = '0'; Expected = 'Completed' }
        @{ Recurrence = '15m'; Expected = 'Planned' }
    ) {
        $Result = Push-ExecScheduledCommand -Item (New-TaskItem -Recurrence $Recurrence)

        $Result | Should -Be 'Task Completed Successfully.'
        $script:Writes[-1].TaskState | Should -Be $Expected
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $message -like 'Successfully executed task*' }
    }
}

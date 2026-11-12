# An alert the tenant's cloud does not support (redanthrax/CIPP#4) is skipped for that tenant: recorded as Skipped,
# one informational log line, the task moved to its next slot, the alert never called. Commercial tenants run it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:RepoRoot = $RepoRoot
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-ExecScheduledCommand.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPScheduledTaskNextRun.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPCloudFeatureSupport.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-CIPPCloudFeatureSupport.ps1')

    function Get-CIPPTenantRequestCloud { param($TenantFilter) }
    function Set-CippScheduledTaskContext { param($TaskId, $AlertReNotify, $AlertRun) }
    function Set-CippUserAgentContext { param($Headers, $Source, $TaskId) }
    function Get-CippTable { param($tablename) }
    function Get-AzDataTableEntity { param($Context, $Filter) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Add-CIPPAlertRunHistory { param($Task, $Tenant, $TenantId, $Outcome, $Summary, $Counts, $StartedUtc, $ScheduledTime, $DurationMs, [switch]$RecordCompletion) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPSchedulerBlockedCommands { @() }
    function Write-LogMessage { param($headers, $API, $message, $sev, $tenant, $tenantid, $LogData) }
    function Send-CIPPScheduledTaskAlert { param($Results, $TaskInfo, $TenantFilter, $TaskType, $Attachments) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    # The executor only runs functions from the CIPP modules, so the alerts live in a module of that name.
    $null = New-Module -Name CIPPAlerts -ScriptBlock {
        function Get-CIPPAlertDefenderStatus { param($TenantFilter, $InputValue, $Headers) }
        function Get-CIPPAlertMFAAlertUsers { param($TenantFilter, $InputValue, $Headers) }
    } | Import-Module -Force -PassThru

    . $FunctionPath

    function New-AlertItem ([string]$Command) {
        $TaskInfo = [pscustomobject]@{
            PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; Name = 'Defender status'; Command = $Command
            Tenant = 'tenant.example'; Recurrence = '1d'; TaskState = 'Pending'
            ScheduledTime = [string][datetimeoffset]::new([datetime]::UtcNow.Date).ToUnixTimeSeconds()
        }
        [pscustomobject]@{ Command = $Command; Parameters = @{ TenantFilter = 'tenant.example' }; TaskInfo = $TaskInfo }
    }
}

AfterAll {
    Remove-Module -Name CIPPAlerts -Force -ErrorAction SilentlyContinue
}

Describe 'Push-ExecScheduledCommand cloud support' {
    BeforeAll {
        $script:PreviousRoot = $env:CIPPRootPath
        $env:CIPPRootPath = $TestDrive
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'Config') -Force | Out-Null
        '[{"name":"DefenderStatus"}]' | Set-Content -Path (Join-Path $TestDrive 'Config/alerts.json')
        Copy-Item -Path (Join-Path $script:RepoRoot 'Config/cloudFeatureSupport.json') -Destination (Join-Path $TestDrive 'Config/cloudFeatureSupport.json')
    }
    AfterAll { $env:CIPPRootPath = $script:PreviousRoot }

    BeforeEach {
        $script:CIPPCloudFeatureSupport = $null
        Mock Set-CippScheduledTaskContext {}
        Mock Set-CippUserAgentContext {}
        Mock Get-CippTable { @{ Context = 'stub' } }
        Mock Update-AzDataTableEntity {}
        Mock Add-CIPPAzDataTableEntity {}
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'cust-1' } }
        Mock Write-LogMessage {}
        Mock Send-CIPPScheduledTaskAlert {}
        Mock Add-CIPPAlertRunHistory {}
        Mock Get-AzDataTableEntity { [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'task-1'; TaskState = 'Pending' } }
        Mock Get-CIPPAzDataTableEntity {}
        Mock Get-CIPPAlertDefenderStatus {}
    }

    It 'runs the alert for a Commercial tenant and never reads the matrix' {
        Mock Get-CIPPTenantRequestCloud { 'Commercial' }
        Mock Get-CIPPCloudFeatureSupport {}
        $Result = Push-ExecScheduledCommand -Item (New-AlertItem 'Get-CIPPAlertDefenderStatus') 6>$null

        "$Result" | Should -Not -BeLike 'Task Skipped*'
        Should -Invoke Get-CIPPAlertDefenderStatus -Times 1 -Exactly
        Should -Invoke Get-CIPPCloudFeatureSupport -Times 0 -Exactly
        Should -Invoke Add-CIPPAlertRunHistory -Times 0 -Exactly -ParameterFilter { $Outcome -eq 'Skipped' }
    }

    It 'skips an unsupported alert for a government tenant with one log line and moves the task on' {
        Mock Get-CIPPTenantRequestCloud { 'USGovHigh' }
        $Result = Push-ExecScheduledCommand -Item (New-AlertItem 'Get-CIPPAlertDefenderStatus') 6>$null

        $Result | Should -BeLike 'Task Skipped*'
        Should -Invoke Get-CIPPAlertDefenderStatus -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Info' -and $message -like '*not supported for USGovHigh*' }
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $sev -eq 'Error' }
        Should -Invoke Add-CIPPAlertRunHistory -Times 1 -Exactly -ParameterFilter { $Outcome -eq 'Skipped' -and $TenantId -eq 'cust-1' }
        Should -Invoke Update-AzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.TaskState -eq 'Planned' }
    }

    It 'runs an alert the matrix does not list for a government tenant' {
        Mock Get-CIPPTenantRequestCloud { 'USGovHigh' }
        $Item = New-AlertItem 'Get-CIPPAlertDefenderStatus'
        $Item.Command = 'Get-CIPPAlertMFAAlertUsers'
        Mock Get-CIPPAlertMFAAlertUsers {}
        $Result = Push-ExecScheduledCommand -Item $Item 6>$null

        "$Result" | Should -Not -BeLike 'Task Skipped*'
        Should -Invoke Get-CIPPAlertMFAAlertUsers -Times 1 -Exactly
    }
}

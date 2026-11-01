# Register-CIPPExtensionScheduledTasks can be called for a subset of extensions (the Hudu "reschedule" sync calls it
# with -Extensions Hudu). Its cleanup must only remove tasks of the selected extensions, and must check each task
# against the tenants mapped for its own extension, not the union of every extension's mappings.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Register-CippExtensionScheduledTasks.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Register-CippExtensionScheduledTasks.ps1 under Modules/' }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function Add-CIPPScheduledTask { param($Task, $Hidden, $SyncType) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }

    . $FunctionPath

    function New-TestTask {
        param($Key, $Tenant, $Extension, $Command = 'Push-CippExtensionData')
        [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = $Key; Tenant = "$Tenant.example.com"; SyncType = $Extension; Command = $Command; Name = $Key }
    }
}

Describe 'Register-CIPPExtensionScheduledTasks cleanup' {
    BeforeEach {
        $script:Config = @{ Hudu = @{ Enabled = $true }; NinjaOne = @{ Enabled = $true }; Sherweb = @{ Enabled = $true; AutoMigrations = $true } }
        $script:Tasks = @()
        $script:Mappings = @{ Hudu = @('a'); NinjaOne = @('a'); Sherweb = @('b') }
        $script:CustomMappings = @()
        $script:Added = [System.Collections.Generic.List[object]]::new()
        $script:Removed = [System.Collections.Generic.List[string]]::new()

        Mock Get-CIPPTable { @{ TableName = $TableName } }
        Mock Get-Tenants {
            foreach ($Id in 'a', 'b', 'c') { [pscustomobject]@{ customerId = $Id; defaultDomainName = "$Id.example.com" } }
        }
        Mock Get-CIPPAzDataTableEntity {
            switch ($TableName) {
                'Extensionsconfig' { [pscustomobject]@{ config = ($script:Config | ConvertTo-Json -Depth 5 -Compress) } }
                'ScheduledTasks' { $script:Tasks }
                'CustomDataMappings' { $script:CustomMappings }
                'CippMapping' {
                    foreach ($Name in 'Hudu', 'NinjaOne', 'Sherweb') {
                        if ($Filter -eq "PartitionKey eq '$($Name)Mapping'") {
                            foreach ($Id in $script:Mappings[$Name]) { [pscustomobject]@{ RowKey = $Id } }
                        }
                    }
                }
                default { throw "Unexpected table $TableName" }
            }
        }
        Mock Add-CIPPScheduledTask { $script:Added.Add([pscustomobject]@{ Task = $Task; SyncType = $SyncType }) }
        Mock Remove-CIPPAzDataTableEntity { $script:Removed.Add($Entity.RowKey) }
    }

    It 'keeps other extensions'' tasks during a Hudu-only reschedule' {
        $script:Tasks = @(
            (New-TestTask 'custom-b' 'b' 'CustomData'),
            (New-TestTask 'custom-a' 'a' 'CustomData'),
            (New-TestTask 'sherweb-c' 'c' 'Sherweb' 'Invoke-SherwebMigration')
        )

        Register-CIPPExtensionScheduledTasks -Extensions Hudu -Reschedule -NextSync 1800000000

        $script:Removed.Count | Should -Be 0
        $script:Added.Count | Should -Be 1
        $script:Added[0].SyncType | Should -Be 'Hudu'
    }

    It 'removes a Hudu task for an unmapped tenant even when CustomData covers that tenant' {
        $script:Tasks = @((New-TestTask 'hudu-b' 'b' 'Hudu'))
        $script:CustomMappings = @([pscustomobject]@{ JSON = '{"sourceType":{"value":"reportingDb"},"tenantFilter":{"value":["AllTenants"]}}' })

        Register-CIPPExtensionScheduledTasks -Extensions Hudu, CustomData

        $script:Removed.ToArray() | Should -Be @('hudu-b')
    }

    It 'removes a Sherweb migration task for an unmapped tenant even when Hudu maps that tenant' {
        $script:Mappings.Hudu = @('c')
        $script:Tasks = @((New-TestTask 'sherweb-c' 'c' 'Sherweb' 'Invoke-SherwebMigration'))

        Register-CIPPExtensionScheduledTasks -Extensions Hudu, Sherweb

        $script:Removed.ToArray() | Should -Be @('sherweb-c')
        @($script:Added | Where-Object SyncType -EQ 'Sherweb').Count | Should -Be 1
    }

    It 'removes a disabled extension''s tasks once and leaves other extensions alone' {
        $script:Config.Hudu.Enabled = $false
        $script:Tasks = @((New-TestTask 'hudu-a' 'a' 'Hudu'), (New-TestTask 'custom-b' 'b' 'CustomData'))

        Register-CIPPExtensionScheduledTasks -Extensions Hudu

        $script:Removed.ToArray() | Should -Be @('hudu-a')
        $script:Added.Count | Should -Be 0
    }

    It 'keeps a mapped task when nothing changed' {
        $script:Tasks = @((New-TestTask 'hudu-a' 'a' 'Hudu'))

        Register-CIPPExtensionScheduledTasks -Extensions Hudu

        $script:Removed.Count | Should -Be 0
        $script:Added.Count | Should -Be 0
    }
}

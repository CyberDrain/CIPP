# Pester tests for Invoke-ListAuditLogs paging: every saved log of every allowed tenant exactly once, page by page.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListAuditLogs.ps1' -File)[0].FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property, $First) }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) ([string]$Value) -replace "'", "''" }
    . $FunctionPath

    function Invoke-Page($Query) { Invoke-ListAuditLogs -Request ([pscustomobject]@{ Query = [pscustomobject]$Query }) -TriggerMetadata $null }
}

Describe 'Invoke-ListAuditLogs paging' {
    BeforeEach {
        # Saved logs of thirty allowed tenants (mixed case, like real ones, and enough that a walk needs more than one
        # request's 25 table queries) and one the caller may not see, returned in whatever order the store likes.
        $script:Allowed = @('CyberDrainDev.onmicrosoft.com') + @(foreach ($t in 1..29) { "tenant$t.onmicrosoft.com" })
        $script:Rows = @(foreach ($Tenant in @($script:Allowed) + @('hidden.com')) {
                foreach ($n in 1..3) { [pscustomobject]@{ PartitionKey = $Tenant; RowKey = ('{0:D3}-{1}' -f $n, [guid]::NewGuid()); Tenant = $Tenant; Title = 'alert'; Data = '{"RawData":{"Operation":"New-InboxRule","CreationTime":"2026-10-24T10:00:00"}}' } }
            }) | Sort-Object { Get-Random }
        $script:Queries = 0
        Mock Get-Tenants { $script:Allowed | ForEach-Object { [pscustomobject]@{ defaultDomainName = $_ } } }
        # Applies the partition, the resume point and -First, as the table service does.
        Mock Get-CIPPAzDataTableEntity {
            $script:Queries++
            $Pk = [regex]::Match($Filter, "PartitionKey eq '([^']*)'").Groups[1].Value
            $After = [regex]::Match($Filter, "RowKey gt '([^']*)'")
            $Matched = @($script:Rows | Where-Object { $_.PartitionKey -ceq $Pk -and (-not $After.Success -or [string]::CompareOrdinal($_.RowKey, $After.Groups[1].Value) -gt 0) } | Sort-Object { $_.RowKey } -Culture ([cultureinfo]::InvariantCulture))
            @($Matched | Select-Object -First $First)
        }
    }

    It 'returns every allowed tenant''s saved logs once across its pages, and none of another tenant''s' {
        $Seen = [System.Collections.Generic.List[string]]::new()
        $Query = @{ tenantFilter = 'AllTenants'; manualPagination = $true }
        $Pages = 0
        do {
            $Response = Invoke-Page $Query
            $Pages++
            foreach ($Row in $Response.Body.Results) { $Seen.Add("$($Row.Tenant)/$($Row.LogId)") }
            $Query.nextLink = $Response.Body.Metadata.nextLink
        } while ($Query.nextLink -and $Pages -lt 20)
        $Pages | Should -BeGreaterThan 1
        $Seen | Should -HaveCount 90
        @($Seen | Select-Object -Unique) | Should -HaveCount 90
        @($Seen | Where-Object { $_ -like 'hidden.com/*' }) | Should -HaveCount 0
        $Query.nextLink | Should -BeNullOrEmpty
    }

    It 'pages one tenant when one is selected' {
        $Response = Invoke-Page @{ tenantFilter = 'tenant7.onmicrosoft.com'; manualPagination = $true }
        @($Response.Body.Results.Tenant | Select-Object -Unique) | Should -Be @('tenant7.onmicrosoft.com')
        @($Response.Body.Results) | Should -HaveCount 3
        $Response.Body.Metadata.nextLink | Should -BeNullOrEmpty
    }

    It 'returns everything in one response without manualPagination' {
        Mock Get-CIPPAzDataTableEntity { $script:Rows }
        $Response = Invoke-Page @{ tenantFilter = 'AllTenants' }
        @($Response.Body.Results) | Should -HaveCount 90
    }
}

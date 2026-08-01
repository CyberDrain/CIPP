function Get-CIPPDbCoverage {
    <#
    .SYNOPSIS
        Describes reporting database coverage for a cache type.

    .DESCRIPTION
        Compares the per-tenant count rows written by Add-CIPPDbItem -AddCount with the
        current managed tenant list and the records returned to the caller. This makes
        missing, zero-row, stale, and unparseable tenant data observable.

    .PARAMETER TenantFilter
        The tenant domain or 'AllTenants'.

    .PARAMETER Type
        The reporting database cache type.

    .PARAMETER Results
        The parsed records returned for the same tenant and type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantFilter,

        [Parameter(Mandatory)]
        [string]$Type,

        [AllowEmptyCollection()]
        [object[]]$Results = @()
    )

    $IsAllTenants = $TenantFilter -eq 'AllTenants'
    $ExpectedTenants = if ($IsAllTenants) {
        @((Get-Tenants -IncludeErrors).defaultDomainName | Where-Object { $_ })
    } else {
        @((Get-Tenants -TenantFilter $TenantFilter).defaultDomainName | Where-Object { $_ })
    }

    $DbTenantFilter = if ($IsAllTenants) { 'allTenants' } else { $ExpectedTenants[0] }
    $CountRows = if ($DbTenantFilter) {
        @(Get-CIPPDbItem -TenantFilter $DbTenantFilter -Type $Type -CountsOnly)
    } else {
        @()
    }

    $CountsByTenant = @{}
    foreach ($CountRow in $CountRows) {
        if ($CountRow.PartitionKey) { $CountsByTenant[$CountRow.PartitionKey] = $CountRow }
    }

    $ReturnedByTenant = @{}
    if ($IsAllTenants) {
        foreach ($Group in @($Results | Where-Object { $_.Tenant } | Group-Object Tenant)) {
            $ReturnedByTenant[$Group.Name] = $Group.Count
        }
    } elseif ($ExpectedTenants.Count -eq 1) {
        $ReturnedByTenant[$ExpectedTenants[0]] = @($Results).Count
    }

    $TenantCoverage = foreach ($Tenant in $ExpectedTenants) {
        $CountRow = $CountsByTenant[$Tenant]
        $ExpectedCount = if ($null -ne $CountRow) { [int]$CountRow.DataCount } else { $null }
        $ReturnedCount = if ($ReturnedByTenant.ContainsKey($Tenant)) { [int]$ReturnedByTenant[$Tenant] } else { 0 }
        [PSCustomObject]@{
            Tenant            = $Tenant
            Available         = $null -ne $CountRow
            DataCount         = $ExpectedCount
            ReturnedDataCount = $ReturnedCount
            Timestamp         = if ($CountRow) { $CountRow.Timestamp } else { $null }
            Complete          = $null -ne $CountRow -and $ExpectedCount -eq $ReturnedCount
        }
    }

    $MissingTenants = @($TenantCoverage | Where-Object { -not $_.Available } | Select-Object -ExpandProperty Tenant)
    $IncompleteTenants = @($TenantCoverage | Where-Object { -not $_.Complete } | Select-Object -ExpandProperty Tenant)

    [PSCustomObject]@{
        Type                 = $Type
        Complete             = $IncompleteTenants.Count -eq 0
        ExpectedTenantCount  = $ExpectedTenants.Count
        AvailableTenantCount = @($TenantCoverage | Where-Object Available).Count
        DataCount            = [int](($TenantCoverage | Measure-Object DataCount -Sum).Sum ?? 0)
        ReturnedDataCount    = @($Results).Count
        MissingTenants       = $MissingTenants
        IncompleteTenants    = $IncompleteTenants
        Tenants              = @($TenantCoverage)
    }
}

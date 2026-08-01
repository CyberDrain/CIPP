function New-CIPPDbRequest {
    <#
    .SYNOPSIS
        Query the CIPP Reporting database by partition key

    .DESCRIPTION
        Retrieves data from the CippReportingDB table filtered by partition key (tenant).

        Rows are parsed by CIPP.CippJson (System.Text.Json), not ConvertFrom-Json — see .NOTES.
        Most callers should use Get-CIPPTestData instead, which adds the shared cache and applies
        the per-type field manifest automatically. Call this directly only to bypass both.

    .PARAMETER TenantFilter
        The tenant domain or GUID to filter by (used as partition key)

    .PARAMETER Type
        Optional. The data type to filter by (e.g., Users, Groups, Devices)

    .PARAMETER Fields
        Optional. Keep only these top-level fields on each returned record; everything else is
        skipped without being materialized. A retained field keeps its ENTIRE subtree — projection
        never reaches inside a kept value, so `$p.conditions.users.includeRoles` only requires
        'conditions'. Omit to return every field. Matching is case-insensitive.

        This is the only memory lever, but its value depends entirely on which fields you keep: it
        pays where records are large and the read-set is small, and buys almost nothing where the
        retained subtrees are most of the payload. Measure before assuming a win.

    .NOTES
        Backed by CIPP.CippJson (System.Text.Json). Output is PSCustomObject with
        ConvertFrom-Json's [DateTime] coercion and Int64 number semantics preserved deliberately,
        so this is a drop-in replacement for every existing caller. Matching those semantics costs
        nothing measurable — do not reintroduce divergence to save a branch.

        Unparseable rows are skipped rather than thrown, matching the -ErrorAction SilentlyContinue
        on the ConvertFrom-Json this replaced. A row whose Data is a JSON array returns object[],
        which PowerShell unrolls into the output stream — the same shape the old pipeline produced.

        Without -Fields the parser alone is modestly faster and allocates less, but retains the
        same live bytes — the parser was never the memory cost. Only -Fields reduces footprint.

        Benchmark on production's runtime (PowerShell 7.4 / .NET 8, Linux container).
        System.Text.Json timings differ enough on newer runtimes to invert conclusions;
        allocation numbers are runtime-insensitive.

    .EXAMPLE
        New-CIPPDbRequest -TenantFilter 'contoso.onmicrosoft.com'

    .EXAMPLE
        New-CIPPDbRequest -TenantFilter 'contoso.onmicrosoft.com' -Type 'Users'

    .EXAMPLE
        New-CIPPDbRequest -TenantFilter 'contoso.onmicrosoft.com' -Type 'Users' -Fields 'id','displayName'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$Type,

        [Parameter(Mandatory = $false)]
        [string[]]$Fields
    )

    try {
        # Enforce tenant lock when running inside custom script execution
        if ($script:CIPPLockedTenant) {
            $TenantFilter = $script:CIPPLockedTenant
        }

        if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
            throw 'TenantFilter is required.'
        }

        $Table = Get-CippTable -tablename 'CippReportingDB'

        $IsAllTenants = $TenantFilter -eq 'AllTenants'

        if ($IsAllTenants) {
            $Tenant = 'AllTenants'
            $ValidTenants = [System.Collections.Generic.HashSet[string]]::new(
                [string[]]@((Get-Tenants -IncludeErrors).defaultDomainName),
                [System.StringComparer]::OrdinalIgnoreCase
            )
        } elseif (-not $script:CIPPDbRequestTenantCache) {
            $script:CIPPDbRequestTenantCache = @{}
        }

        if (-not $IsAllTenants) {
            $CacheNow = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            $CachedTenant = $script:CIPPDbRequestTenantCache[$TenantFilter]
            if ($CachedTenant -and ($CacheNow - $CachedTenant.Timestamp) -lt 300) {
                $Tenant = $CachedTenant.DefaultDomain
            } else {
                $Tenant = (Get-Tenants -TenantFilter $TenantFilter).defaultDomainName
                if ($Tenant) {
                    $script:CIPPDbRequestTenantCache[$TenantFilter] = @{ DefaultDomain = $Tenant; Timestamp = $CacheNow }
                }
            }
        }
        if (-not $Tenant) {
            if ($TenantFilter -eq $env:TenantID) {
                return $false
            }
            throw "Tenant '$TenantFilter' not found"
        }
        $SafeTypeFilter = if ($Type) { ConvertTo-CIPPODataFilterValue -Value $Type -Type String } else { $null }

        if ($IsAllTenants -and $Type) {
            $Filter = "RowKey ge '{0}-' and RowKey lt '{0}.'" -f $SafeTypeFilter
        } elseif ($IsAllTenants) {
            $Filter = $null
        } elseif ($Type) {
            $SafeTenantFilter = ConvertTo-CIPPODataFilterValue -Value $Tenant -Type String
            $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}-' and RowKey lt '{1}.'" -f $SafeTenantFilter, $SafeTypeFilter
        } else {
            $SafeTenantFilter = ConvertTo-CIPPODataFilterValue -Value $Tenant -Type String
            $Filter = "PartitionKey eq '{0}'" -f $SafeTenantFilter
        }

        $Results = if ($Filter) { Get-CIPPAzDataTableEntity @Table -Filter $Filter } else { Get-CIPPAzDataTableEntity @Table }

        # CippJson replaces `$Results.Data | ConvertFrom-Json`. A row whose Data is a JSON array
        # returns object[], which PowerShell unrolls into the output stream — the same shape the
        # pipeline produced before. Bad rows are skipped rather than thrown, matching the
        # -ErrorAction SilentlyContinue this replaced.
        $Projection = if ($Fields) { [string[]]$Fields } else { $null }
        $Output = foreach ($Row in $Results) {
            if ($IsAllTenants -and -not $ValidTenants.Contains($Row.PartitionKey)) { continue }
            if ([string]::IsNullOrWhiteSpace($Row.Data)) { continue }
            try {
                $ParsedItems = @([CIPP.CippJson]::ConvertFromJson($Row.Data, $Projection))
                foreach ($ParsedItem in $ParsedItems) {
                    if ($IsAllTenants -and $null -ne $ParsedItem) {
                        $ParsedItem | Add-Member -NotePropertyName Tenant -NotePropertyValue $Row.PartitionKey -Force
                    }
                    $ParsedItem
                }
            } catch {
                Write-Information "Skipping unparseable CippReportingDB row for '$Tenant'/'$Type': $($_.Exception.Message)"
            }
        }
        return $Output
    } catch {
        Write-LogMessage -API 'CIPPDbRequest' -tenant $TenantFilter -message "Failed to query database: $($_.Exception.Message)" -sev Error
        throw
    }
}

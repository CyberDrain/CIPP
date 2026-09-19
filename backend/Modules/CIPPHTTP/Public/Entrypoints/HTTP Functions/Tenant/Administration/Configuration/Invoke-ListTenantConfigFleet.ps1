function Invoke-ListTenantConfigFleet {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Config.Read
    .DESCRIPTION
        Fleet (All Tenants) view for the Tenant Configuration page: returns one cached row per
        tenant for a given reporting-cache type, so a single request renders every tenant's
        current values. Live per-tenant reads are done by each area's own List endpoint; the
        fleet view is cache-backed because live-calling every tenant is not feasible.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # The reporting-cache type to project across all tenants
    $Type = $Request.Query.type

    # Only tenant-configuration cache types may be projected here
    $AllowedTypes = @(
        'SharePointAdminSettings'
        'ExoOrganizationConfig'
        'ExoAdminAuditLogConfig'
        'AdminReportSettings'
        'AuthorizationPolicy'
        'CrossTenantAccessPolicy'
        'CsTeamsMeetingPolicy'
        'CsTeamsMessagingPolicy'
        'CsExternalAccessPolicy'
        'CsTeamsClientConfiguration'
    )

    try {
        if (-not $Type) { throw 'A type is required.' }
        if ($Type -notin $AllowedTypes) { throw "Unsupported configuration type '$Type'." }

        $Table = Get-CippTable -TableName 'CippReportingDB'
        # RowKeys are '<Type>-<id>'; the range bounds the scan to this type across all partitions.
        $Filter = "RowKey ge '{0}-' and RowKey lt '{0}.'" -f $Type
        $Rows = Get-CIPPAzDataTableEntity @Table -Filter $Filter

        $Result = foreach ($Row in $Rows) {
            if ($Row.RowKey -eq "$Type-Count") { continue }
            if (-not $Row.Data) { continue }
            $Object = $Row.Data | ConvertFrom-Json
            # Stamp the owning tenant so the fleet table can key each row
            $Object | Add-Member -NotePropertyName Tenant -NotePropertyValue $Row.PartitionKey -Force
            $Object
        }

        $StatusCode = [HttpStatusCode]::OK
        $Body = @($Result)
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ Results = $_.Exception.Message }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

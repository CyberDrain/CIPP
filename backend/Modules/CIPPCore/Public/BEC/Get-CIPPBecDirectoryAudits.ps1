function Get-CIPPBecDirectoryAudits {
    <#
    .SYNOPSIS
        Collects the Entra directory-audit events that targeted, or were initiated by, the investigated user.
    .DESCRIPTION
        Queries auditLogs/directoryAudits twice in one batch - once with targetResources/any(id eq user)
        and once with initiatedBy/user/id eq user (the two cannot be or-combined on this endpoint) -
        de-duplicates on id and flags the activities that matter during a compromise investigation
        (security-info registration, consent, service principals, device registration, password and
        token events, role changes) from the heuristics file. Metadata only: the audit record's
        activity name, actor, IP, targets and modified property names.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The user's object id.
    .PARAMETER StartDate
        Window start (UTC).
    .PARAMETER Heuristics
        The BEC heuristics object (directoryAudit.flaggedActivities).
    .PARAMETER Cap
        Maximum rows per direction.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [Parameter(Mandatory = $true)]$Heuristics,
        [int]$Cap = 500
    )

    $SafeId = ConvertTo-CIPPODataFilterValue -Value $UserId -Type Guid
    $Start = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $Select = 'id,activityDateTime,activityDisplayName,category,result,resultReason,initiatedBy,targetResources,loggedByService'
    $Requests = @(
        @{ id = 'Target'; method = 'GET'; url = "auditLogs/directoryAudits?`$filter=activityDateTime ge $Start and targetResources/any(t:t/id eq '$SafeId')&`$top=$Cap&`$select=$Select"; headers = @{ ConsistencyLevel = 'eventual' } }
        @{ id = 'Actor'; method = 'GET'; url = "auditLogs/directoryAudits?`$filter=activityDateTime ge $Start and initiatedBy/user/id eq '$SafeId'&`$top=$Cap&`$select=$Select"; headers = @{ ConsistencyLevel = 'eventual' } }
    )
    $Responses = New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true

    $Flagged = @($Heuristics.directoryAudit.flaggedActivities)
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new()
    $Rows = [System.Collections.Generic.List[object]]::new()
    $Capped = $false
    foreach ($Direction in @('Target', 'Actor')) {
        $Response = $Responses | Where-Object { $_.id -eq $Direction } | Select-Object -First 1
        if (-not $Response) { $Errors.Add("$Direction query returned no response"); continue }
        if ([int]$Response.status -ge 400) { $Errors.Add("$Direction query: $($Response.body.error.message ?? "status $($Response.status)")"); continue }
        $Items = @($Response.body.value)
        if ($Items.Count -ge $Cap -or $Response.body.'@odata.nextLink') { $Capped = $true }
        foreach ($Item in $Items) {
            if (-not $Item.id -or -not $Seen.Add([string]$Item.id)) { continue }
            $Actor = if ($Item.initiatedBy.user) { $Item.initiatedBy.user.userPrincipalName ?? $Item.initiatedBy.user.displayName ?? $Item.initiatedBy.user.id } elseif ($Item.initiatedBy.app) { $Item.initiatedBy.app.displayName ?? $Item.initiatedBy.app.appId } else { $null }
            $ActorType = if ($Item.initiatedBy.user) { 'User' } elseif ($Item.initiatedBy.app) { 'Application' } else { 'Unknown' }
            $Targets = @(foreach ($T in @($Item.targetResources)) { $T.userPrincipalName ?? $T.displayName ?? $T.id })
            $Modified = @(foreach ($T in @($Item.targetResources)) {
                    foreach ($P in @($T.modifiedProperties)) {
                        if (-not $P.displayName) { continue }
                        $NewValue = [string]$P.newValue
                        if ($NewValue.Length -gt 200) { $NewValue = $NewValue.Substring(0, 200) + '...' }
                        "$($P.displayName)=$NewValue"
                    }
                })
            $Activity = [string]$Item.activityDisplayName
            $IsFlagged = ($Activity -in $Flagged) -or ($Activity -like 'User registered*security info*') -or ($Activity -like '*Strong Authentication*')
            $Rows.Add([pscustomobject]@{
                    Id                  = $Item.id
                    ActivityDateTime    = if ($Item.activityDateTime) { ([datetime]$Item.activityDateTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                    Activity            = $Activity
                    Category            = $Item.category
                    Service             = $Item.loggedByService
                    Result              = $Item.result
                    ResultReason        = $Item.resultReason
                    InitiatedBy         = $Actor
                    InitiatedByType     = $ActorType
                    ClientIP            = $Item.initiatedBy.user.ipAddress
                    Targets             = ($Targets -join ', ')
                    ModifiedProperties  = ($Modified -join '; ')
                    Direction           = $Direction
                    Flagged             = [bool]$IsFlagged
                })
        }
    }

    $Data = @($Rows | Sort-Object -Property @{ Expression = { $_.Flagged }; Descending = $true }, @{ Expression = { $_.ActivityDateTime }; Descending = $true })
    $ErrorText = if ($Errors.Count -gt 0) { $Errors -join '; ' } else { $null }
    return New-CIPPBecCollectorResult -Data $Data -Complete (-not $Capped -and $Errors.Count -eq 0) -Cap ($(if ($Capped) { "$Cap rows per direction" } else { $null })) -Error $ErrorText
}

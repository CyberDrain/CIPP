function Get-CIPPBecNonInteractiveSignIns {
    <#
    .SYNOPSIS
        Collects the investigated user's most recent non-interactive sign-ins.
    .DESCRIPTION
        Token replay and adversary-in-the-middle sessions show up as non-interactive sign-ins (refresh
        token use, background token acquisition) rather than in the interactive log the Quick scope
        reads. This reads the beta signIns endpoint filtered on signInEventTypes nonInteractiveUser,
        projects the same fields as the interactive list and marks each row as inside or outside the
        user's assigned usage location.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The user's object id.
    .PARAMETER UsageLocation
        The user's Entra usage location (ISO country code) for the foreign-location comparison.
    .PARAMETER Top
        Number of sign-ins to return (newest first).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserId,
        [string]$UsageLocation,
        [ValidateRange(1, 1000)][int]$Top = 50
    )

    $SafeId = ConvertTo-CIPPODataFilterValue -Value $UserId -Type Guid
    $Uri = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=userId eq '$SafeId' and signInEventTypes/any(t: t eq 'nonInteractiveUser')&`$top=$Top&`$orderby=createdDateTime desc"
    $SignIns = @(New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -AsApp $true -noPagination $true)

    $Rows = foreach ($SignIn in $SignIns) {
        if (-not $SignIn.id) { continue }
        $Country = $SignIn.location.countryOrRegion
        $Foreign = if (-not $UsageLocation -or [string]::IsNullOrWhiteSpace($Country) -or $Country -eq 'Unknown') { $null } else { ($Country -ne $UsageLocation) }
        [pscustomobject]@{
            CreatedDateTime     = if ($SignIn.createdDateTime) { ([datetime]$SignIn.createdDateTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
            id                  = $SignIn.id
            AppDisplayName      = $SignIn.appDisplayName
            ResourceDisplayName = $SignIn.resourceDisplayName
            ClientAppUsed       = $SignIn.clientAppUsed
            Status              = if ($SignIn.conditionalAccessStatus -in @('success', 'notApplied') -and $SignIn.status.errorCode -eq 0) { 'Success' } else { 'Failed' }
            ErrorCode           = $SignIn.status.errorCode
            IPAddress           = $SignIn.ipAddress
            Country             = $Country
            City                = $SignIn.location.city
            UserAgent           = $SignIn.userAgent
            IncomingTokenType   = $SignIn.incomingTokenType
            TokenProtection     = $SignIn.tokenProtectionStatusDetails.signInSessionStatus
            RiskLevelDuringSignIn = $SignIn.riskLevelDuringSignIn
            ForeignLocation     = $Foreign
        }
    }
    $Data = @($Rows)
    return New-CIPPBecCollectorResult -Data $Data -Complete ($Data.Count -lt $Top) -Cap ($(if ($Data.Count -ge $Top) { "$Top most recent sign-ins" } else { $null }))
}

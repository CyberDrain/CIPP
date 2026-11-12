function Invoke-EditTenantCloudEnvironment {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    .DESCRIPTION
        Manually sets the Microsoft cloud a tenant lives in (Commercial, USGovHigh or USGovDoD), overriding the value detected when the tenant was added. Use this for DoD tenants, which detection may report as USGovHigh. Requires unrestricted tenant access, the same as adding a tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # The cloud decides which identity authority, app credentials and API hosts CIPP uses for the
    # tenant, so changing it is held to the same bar as onboarding the tenant (Invoke-ExecAddTenant):
    # CIPP.AppSettings.ReadWrite and unrestricted tenant scope. Checked before anything else so a
    # restricted caller cannot reach the tenant lookup (which can trigger a GDAP rebuild) either.
    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body       = @{ Results = 'Changing a tenant cloud environment requires unrestricted tenant access' }
            })
    }

    $AllowedValues = @('Commercial', 'USGovHigh', 'USGovDoD')

    $customerId = $Request.Body.customerId
    # The cloud to set: Commercial, USGovHigh or USGovDoD - a plain string or the { label, value } object an autocomplete field sends.
    $RequestedValue = $Request.Body.cloudEnvironment.value ?? $Request.Body.cloudEnvironment

    if ([string]::IsNullOrWhiteSpace($customerId)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Missing required parameter: customerId' }
            })
    }

    # Exact, case-sensitive match only: the stored value is compared exactly when choosing endpoints,
    # so anything but a canonical value is rejected rather than guessed at. The input is not echoed back.
    $CloudEnvironment = $AllowedValues | Where-Object { $RequestedValue -is [string] -and $_ -ceq $RequestedValue } | Select-Object -First 1
    if (-not $CloudEnvironment) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Invalid cloudEnvironment. Allowed values: $($AllowedValues -join ', ')" }
            })
    }

    # Get-Tenants is still narrowed to the caller's allowed tenants (defence in depth); no match
    # means unknown or out-of-scope, either way nothing may be written
    $Tenant = Get-Tenants -TenantFilter $customerId | Select-Object -First 1
    if (-not $Tenant) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body       = @{ Results = "Tenant '$customerId' not found or access denied" }
            })
    }

    try {
        $TenantsTable = Get-CippTable -tablename 'Tenants'
        $Entity = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $Tenant.customerId)'"
        if (-not $Entity) { throw "Tenant row for $($Tenant.customerId) not found" }

        # A row with no stored cloud is in the partner cloud, the same default Get-Tenants and the token
        # routing use; with CIPP_PARTNER_CLOUD unset that is Commercial (redanthrax/CIPP#3).
        $Previous = if ($Entity.cloudEnvironment) { [string]$Entity.cloudEnvironment } elseif ([string]::IsNullOrEmpty($env:CIPP_PARTNER_CLOUD)) { 'Commercial' } else { Get-CIPPPartnerCloudEnvironment }
        # A direct tenant's stored refresh token was issued by the authority of the cloud it was added in:
        # login.microsoftonline.com for Commercial, login.microsoftonline.us for USGovHigh and USGovDoD. A change
        # that crosses those authorities would send that token to the other one, so refuse it in both
        # directions; the tenant has to be removed and added again in the new cloud. USGovHigh <-> USGovDoD
        # share an authority and stays allowed (redanthrax/CIPP#3).
        if ($Entity.delegatedPrivilegeStatus -eq 'directTenant' -and (($Previous -ceq 'Commercial') -ne ($CloudEnvironment -ceq 'Commercial'))) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "$($Tenant.displayName) is a direct tenant added in $Previous, and its stored sign-in can only be used there. To move it to $CloudEnvironment, remove the tenant and add it again, choosing $CloudEnvironment when you sign in." }
                })
        }
        $Entity | Add-Member -NotePropertyName 'cloudEnvironment' -NotePropertyValue $CloudEnvironment -Force
        Add-CIPPAzDataTableEntity @TenantsTable -Entity $Entity -Force | Out-Null
        # Tokens are routed by cloud (redanthrax/CIPP#2): drop this tenant's cached tokens and cloud marker
        # so the next request uses the new cloud's authority and app.
        $null = Clear-CippTokenCache -TenantFilter $Tenant.customerId

        $Message = "Changed cloud environment for $($Tenant.displayName) from $Previous to $CloudEnvironment"
        Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant.defaultDomainName -TenantId $Tenant.customerId -message $Message -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
        $Body = @{ Results = $Message }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant.defaultDomainName -TenantId $Tenant.customerId -message "Failed to set cloud environment: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ Results = "Failed to set cloud environment: $($ErrorMessage.NormalizedError)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

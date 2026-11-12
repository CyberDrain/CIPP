function Invoke-EditTenantCloudEnvironment {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    .DESCRIPTION
        Manually sets a tenant's Microsoft cloud (Commercial, USGovHigh or USGovDoD), e.g. for a DoD tenant detected as USGovHigh.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Same bar as onboarding; checked first so a restricted caller can't trigger the tenant lookup.
    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body       = @{ Results = 'Changing a tenant cloud environment requires unrestricted tenant access' }
            })
    }

    $AllowedValues = @('Commercial', 'USGovHigh', 'USGovDoD')

    $customerId = $Request.Body.customerId
    $RequestedValue = $Request.Body.cloudEnvironment.value ?? $Request.Body.cloudEnvironment

    if ([string]::IsNullOrWhiteSpace($customerId)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Missing required parameter: customerId' }
            })
    }

    # Exact match only; don't echo the input.
    $CloudEnvironment = $AllowedValues | Where-Object { $RequestedValue -is [string] -and $_ -ceq $RequestedValue } | Select-Object -First 1
    if (-not $CloudEnvironment) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Invalid cloudEnvironment. Allowed values: $($AllowedValues -join ', ')" }
            })
    }

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

        $Previous = if ($Entity.cloudEnvironment) { [string]$Entity.cloudEnvironment } elseif ([string]::IsNullOrEmpty($env:CIPP_PARTNER_CLOUD)) { 'Commercial' } else { Get-CIPPPartnerCloudEnvironment }
        # A stored refresh token only works at its cloud's authority; USGovHigh and USGovDoD share one.
        if ($Entity.delegatedPrivilegeStatus -eq 'directTenant' -and (($Previous -ceq 'Commercial') -ne ($CloudEnvironment -ceq 'Commercial'))) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "$($Tenant.displayName) is a direct tenant added in $Previous, and its stored sign-in can only be used there. To move it to $CloudEnvironment, remove the tenant and add it again, choosing $CloudEnvironment when you sign in." }
                })
        }
        $Entity | Add-Member -NotePropertyName 'cloudEnvironment' -NotePropertyValue $CloudEnvironment -Force
        Add-CIPPAzDataTableEntity @TenantsTable -Entity $Entity -Force | Out-Null
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

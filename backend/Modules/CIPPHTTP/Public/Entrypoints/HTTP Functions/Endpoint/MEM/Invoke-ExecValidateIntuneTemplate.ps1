function Invoke-ExecValidateIntuneTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.Read
    .SYNOPSIS
        Check an Intune template for problems that would stop it deploying.
    .DESCRIPTION
        Runs the same checks the store and deploy paths run, and reports everything it finds instead
        of stopping at the first problem. Nothing is written and no policy is deployed.

        Validates either a stored template, by ID, or a payload supplied directly - which is how the
        editor checks an edit before saving it. Supplying a tenant adds the checks that need one:
        whether the replacement variables resolve, and whether an Endpoint Security template keeps
        its settings once filtered to what that tenant offers.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        # GUID of a stored template to validate. Omit when supplying RAWJson directly.
        $ID = $Request.Body.ID ?? $Request.Query.ID
        # Policy payload to validate as-is, instead of reading a stored template.
        $RawJSON = $Request.Body.RAWJson
        # Template type, e.g. Catalog or deviceCompliancePolicies. Inferred from the payload if omitted.
        $TemplateType = $Request.Body.TemplateType
        # Template display name, used to resolve the name the policy would deploy under.
        $DisplayName = $Request.Body.displayName
        # Tenant to run the tenant-specific checks against. Omit for static validation only.
        # The tenant selector sends {value,label}; the API sends a bare string.
        $TenantFilter = $Request.Body.tenantFilter.value ?? $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
        if ($TenantFilter -eq 'AllTenants') { $TenantFilter = $null }

        if (-not $RawJSON) {
            if (-not $ID) {
                throw 'Supply either a template ID or a policy payload to validate.'
            }
            $Table = Get-CippTable -tablename 'templates'
            $SafeID = ConvertTo-CIPPODataFilterValue -Value $ID -Type String
            $Entity = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'IntuneTemplate' and RowKey eq '$SafeID'" | Select-Object -First 1
            if (-not $Entity) {
                throw "No Intune template found with ID $ID."
            }
            $TemplateData = $Entity.JSON | ConvertFrom-Json -Depth 100
            $TemplateData = Repair-CIPPIntuneTemplateNesting -Template $TemplateData -Table $Table
            $RawJSON = $TemplateData.RAWJson
            $TemplateType = $TemplateType ?? $TemplateData.Type
            $DisplayName = $DisplayName ?? $TemplateData.Displayname
        }

        $Params = @{
            RawJSON              = $RawJSON
            TemplateType         = $TemplateType
            DisplayName          = $DisplayName
            # Only worth paying for the catalog here: this is someone asking for a report, not a save.
            IncludeCatalogChecks = $true
        }
        if ($TenantFilter) { $Params.TenantFilter = $TenantFilter }

        $Validation = Test-CIPPIntuneTemplate @Params

        $Results = [System.Collections.Generic.List[object]]::new()
        $Summary = if ($Validation.IsValid -and $Validation.Warnings.Count -eq 0) {
            "Template '$($Validation.DisplayName)' is valid and would deploy as type $($Validation.Type)."
        } elseif ($Validation.IsValid) {
            "Template '$($Validation.DisplayName)' would deploy as type $($Validation.Type), with $($Validation.Warnings.Count) warning(s)."
        } else {
            "Template '$($Validation.DisplayName)' would not deploy: $($Validation.Errors.Count) problem(s) found."
        }
        $Results.Add(@{ resultText = $Summary; state = $Validation.IsValid ? 'success' : 'error' })

        foreach ($Finding in $Validation.Findings) {
            $Prefix = if ($Finding.Path) { "$($Finding.Path): " } else { '' }
            $Results.Add(@{
                    resultText = "$Prefix$($Finding.Message)"
                    state      = $Finding.Severity -eq 'Error' ? 'error' : 'warning'
                    copyField  = $Finding.Code
                })
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Validation failed: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = @($Results) }
        })
}

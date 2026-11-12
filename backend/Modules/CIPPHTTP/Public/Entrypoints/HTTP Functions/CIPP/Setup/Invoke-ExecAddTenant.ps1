function Invoke-ExecAddTenant {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $StatusCode = [HttpStatusCode]::OK
    try {
        # AnyTenant: onboarding writes tenant credentials; require unrestricted tenant scope
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants') {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = @{'message' = 'Adding a tenant requires unrestricted tenant access'; 'severity' = 'error' }
                })
        }

        # Get the tenant ID from the request body
        $tenantId = $Request.body.tenantId
        $defaultDomainName = $Request.body.defaultDomainName

        # The account that consented is recorded so the connection can be traced and refreshed
        # later. The auth date is stamped server side rather than trusting the client.
        $ServiceAccount = $Request.body.username ?? ''
        $AuthDate = (Get-Date).ToUniversalTime()

        $TokenCloud = $null
        $TokenCloudError = $null
        try {
            # Which cloud the sign-in was for (redanthrax/CIPP#2). The consent flow sends the cloud the user
            # picked; absent means Commercial, as before. The token itself has to agree with it.
            $TokenEndpoint = Resolve-CIPPSignInCloud -CloudEnvironment $Request.body.cloudEnvironment -AccessToken ([string]$Request.body.accessToken)
            $TokenCloud = $TokenEndpoint.CloudEnvironment
        } catch {
            $TokenCloudError = $_.Exception.Message
        }

        # Get the Tenants table
        $TenantsTable = Get-CippTable -tablename 'Tenants'
        #force a refresh of the authentication info
        $auth = Get-CIPPAuthentication
        # Check if tenant already exists
        $ExistingTenant = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $tenantId)'"

        if ($tenantId -eq $env:TenantID) {
            # If the tenant is the partner tenant, return an error because you cannot add the partner tenant as direct tenant
            $Results = @{'message' = 'You cannot add the partner tenant as a direct tenant. Please connect the tenant using the "Connect to Partner Tenant" option. '; 'severity' = 'error'; }
            $StatusCode = [HttpStatusCode]::BadRequest
        } elseif ($ExistingTenant -and $ExistingTenant.delegatedPrivilegeStatus -ne 'directTenant') {
            # Converting an existing GDAP tenant in place would silently change how CIPP
            # authenticates to it. Require the tenant to be offboarded first so the switch is
            # deliberate.
            # The sign-in that got us here already stored a per-tenant refresh token, so discard it
            # again - keeping it would leave a credential behind for a conversion we just refused.
            Remove-CIPPDirectTenantToken -TenantId $tenantId

            $Results = @{'message' = "$($ExistingTenant.displayName) is already onboarded as a GDAP tenant and cannot be converted to a Direct Tenant. To manage it as a Direct Tenant, remove the tenant first under Settings > Tenants, then add it again using the Direct Tenant flow."; 'severity' = 'error' }
            $StatusCode = [HttpStatusCode]::BadRequest
            Write-LogMessage -tenant $ExistingTenant.defaultDomainName -tenantid $ExistingTenant.customerId -API 'NewTenant' -message "Blocked conversion of GDAP tenant $($ExistingTenant.displayName) to a Direct Tenant, attempted by $ServiceAccount." -Sev 'Warning'
        } elseif (-not $TokenCloud) {
            # The token's cloud could not be established or contradicts the selected cloud. For a new
            # tenant the sign-in already stored its refresh token; it is not trusted for any cloud, so
            # discard it. An existing direct tenant keeps its token: ExecUpdateRefreshToken refuses to
            # overwrite it with a sign-in that fails this same check, so what is stored is the working one.
            if (-not $ExistingTenant) { Remove-CIPPDirectTenantToken -TenantId $tenantId }
            Write-LogMessage -tenantid $tenantId -API 'NewTenant' -message "Blocked adding or refreshing tenant $tenantId with ${ServiceAccount}: $TokenCloudError" -Sev 'Warning'
            $Results = @{'message' = "The sign-in could not be verified for the selected cloud: $TokenCloudError Choose the cloud the tenant is in and sign in again."; 'severity' = 'error' }
            $StatusCode = [HttpStatusCode]::BadRequest
        } elseif ($ExistingTenant -and $TokenCloud -cne $(if ($ExistingTenant.cloudEnvironment) { [string]$ExistingTenant.cloudEnvironment } elseif ([string]::IsNullOrEmpty($env:CIPP_PARTNER_CLOUD)) { 'Commercial' } else { Get-CIPPPartnerCloudEnvironment })) {
            # A refresh signed in to a different cloud than the one stored for the tenant. The stored refresh
            # token is left alone: ExecUpdateRefreshToken refuses a sign-in for another cloud before
            # storing it, so the stored token is still the tenant's working one (redanthrax/CIPP#2).
            $StoredCloud = if ($ExistingTenant.cloudEnvironment) { $ExistingTenant.cloudEnvironment } else { 'the partner cloud' }
            Write-LogMessage -tenant $ExistingTenant.defaultDomainName -tenantid $ExistingTenant.customerId -API 'NewTenant' -message "Blocked refreshing $($ExistingTenant.displayName): $ServiceAccount signed in to $TokenCloud but the tenant is stored as $StoredCloud." -Sev 'Warning'
            # USGovHigh <-> USGovDoD can be changed in place; Commercial <-> government needs a remove and re-add (redanthrax/CIPP#3).
            $EffectiveStoredCloud = if ($ExistingTenant.cloudEnvironment) { [string]$ExistingTenant.cloudEnvironment } elseif ([string]::IsNullOrEmpty($env:CIPP_PARTNER_CLOUD)) { 'Commercial' } else { Get-CIPPPartnerCloudEnvironment }
            $Remedy = if ($TokenCloud -cne 'Commercial' -and $EffectiveStoredCloud -cne 'Commercial') { "or change the tenant's cloud environment first" } else { "or remove the tenant and add it again in $TokenCloud" }
            $Results = @{'message' = "$($ExistingTenant.displayName) is stored as $StoredCloud, but the sign-in was for $TokenCloud. Sign in again choosing $StoredCloud, $Remedy."; 'severity' = 'error' }
            $StatusCode = [HttpStatusCode]::BadRequest
        } elseif ($ExistingTenant) {
            # Existing direct tenant - refresh the stored credentials and service account details.
            $ExistingTenant | Add-Member -NotePropertyName 'directTenantUserPrincipalName' -NotePropertyValue $ServiceAccount -Force
            $ExistingTenant | Add-Member -NotePropertyName 'directTenantAuthDate' -NotePropertyValue $AuthDate -Force
            Add-CIPPAzDataTableEntity @TenantsTable -Entity $ExistingTenant -Force | Out-Null

            $Results = @{'message' = "Successfully updated the credentials for $($ExistingTenant.displayName)."; 'severity' = 'success' }
            Write-LogMessage -tenant $ExistingTenant.defaultDomainName -tenantid $ExistingTenant.customerId -API 'NewTenant' -message "Refreshed Direct Tenant credentials for $($ExistingTenant.displayName) using $ServiceAccount." -Sev 'Info'
        } else {
            # Create new tenant entry
            try {
                # Get tenant information from Microsoft Graph using bulk request
                $headers = @{ Authorization = "Bearer $($request.body.accessToken)" }

                $BulkRequests = @(
                    @{
                        id     = 'organization'
                        method = 'GET'
                        url    = '/organization?$select=id,displayName'
                    }
                    @{
                        id     = 'domains'
                        method = 'GET'
                        url    = '/domains?$top=999'
                    }
                )

                $BulkBody = @{
                    requests = $BulkRequests
                } | ConvertTo-Json -Depth 10

                # The Graph host of the token's cloud, from the fixed map - never from the request.
                $BulkResponse = Invoke-RestMethod -Uri "$($TokenEndpoint.GraphUrl)/v1.0/`$batch" -Headers $headers -Method POST -Body $BulkBody -ContentType 'application/json' -ErrorAction Stop

                # Parse bulk response
                $OrgResponse = ($BulkResponse.responses | Where-Object { $_.id -eq 'organization' }).body.value
                $DomainsResponse = ($BulkResponse.responses | Where-Object { $_.id -eq 'domains' }).body.value

                $displayName = $OrgResponse.displayName
                $defaultDomainName = ($DomainsResponse | Where-Object { $_.isDefault -eq $true }).id
                $initialDomainName = ($DomainsResponse | Where-Object { $_.isInitial -eq $true }).id
            } catch {
                Write-LogMessage -API 'Add-Tenant' -message "Failed to get information for tenant $tenantId - $($_.Exception.Message)" -Sev 'Critical'
                throw "Failed to get information for tenant $tenantId. Make sure the tenant is properly authenticated."
            }

            # The tenant details come from the consent token, but the row is keyed on the tenantId in
            # the request body. Refuse to add the tenant unless the token belongs to that same tenant,
            # otherwise one tenant's name and domains could be stored under another tenant's id.
            $TokenTenantId = @($OrgResponse.id) | Select-Object -First 1
            if ([string]::IsNullOrWhiteSpace("$TokenTenantId") -or "$TokenTenantId" -ne "$tenantId") {
                Remove-CIPPDirectTenantToken -TenantId $tenantId
                Write-LogMessage -tenantid $tenantId -API 'NewTenant' -message "Blocked adding tenant $tenantId with ${ServiceAccount}: the access token belongs to tenant '$TokenTenantId'." -Sev 'Warning'
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ 'message' = 'The signed-in account does not belong to the tenant being added. Sign in with an account from that tenant and try again.'; 'severity' = 'error' }
                    })
            }

            # Record which Microsoft cloud the tenant lives in. The token (which just worked against that
            # cloud's Graph host) is the strongest evidence; discovery has to agree with it (redanthrax/CIPP#2):
            #   - commercial vs government disagreement: reject, discard the token. Picking either side
            #     would store a tenant under credentials or hosts that do not match it.
            #   - GCC High vs DoD: keep the token's cloud. Discovery separates them only by a region
            #     sub-scope and its domain fallback cannot tell them apart at all (#1), while the token's
            #     audience names the exact Graph host it was accepted by.
            # GCC Moderate is Commercial on both sides. A detection that throws (it is built not to)
            # leaves the token's cloud.
            $CloudEnvironment = $TokenCloud
            try {
                $DetectedCloud = Get-CIPPTenantCloudEnvironment -TenantId $tenantId -InitialDomainName $initialDomainName
            } catch {
                $DetectedCloud = $null
                Write-LogMessage -tenant $defaultDomainName -tenantid $tenantId -API 'NewTenant' -message "Failed to detect the cloud environment for $displayName, using $TokenCloud from the sign-in token: $($_.Exception.Message)" -Sev 'Warning'
            }
            if ($DetectedCloud) {
                $DetectedFamily = if ($DetectedCloud -ceq 'Commercial') { 'Commercial' } else { 'Government' }
                $TokenFamily = if ($TokenCloud -ceq 'Commercial') { 'Commercial' } else { 'Government' }
                if ($DetectedFamily -ne $TokenFamily) {
                    Remove-CIPPDirectTenantToken -TenantId $tenantId
                    Write-LogMessage -tenant $defaultDomainName -tenantid $tenantId -API 'NewTenant' -message "Blocked adding tenant $displayName with ${ServiceAccount}: the sign-in token is for $TokenCloud but the tenant's discovery data says $DetectedCloud. The stored token was discarded." -Sev 'Warning'
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body       = @{ 'message' = "The sign-in was for $TokenCloud, but $displayName looks like a $DetectedCloud tenant. Choose the cloud the tenant is in and sign in again."; 'severity' = 'error' }
                        })
                }
                if ($DetectedCloud -cne $TokenCloud) {
                    Write-LogMessage -tenant $defaultDomainName -tenantid $tenantId -API 'NewTenant' -message "Discovery reports $DetectedCloud for $displayName but the sign-in token is for $TokenCloud. Storing $TokenCloud." -Sev 'Info'
                }
            }

            # Create new tenant object
            $NewTenant = [PSCustomObject]@{
                PartitionKey                  = 'Tenants'
                RowKey                        = $tenantId
                customerId                    = $tenantId
                displayName                   = $displayName
                defaultDomainName             = $defaultDomainName
                initialDomainName             = $initialDomainName
                cloudEnvironment              = $CloudEnvironment
                delegatedPrivilegeStatus      = 'directTenant'
                directTenantUserPrincipalName = $ServiceAccount
                directTenantAuthDate          = $AuthDate
                domains                       = ''
                Excluded                      = $false
                ExcludeUser                   = ''
                ExcludeDate                   = ''
                LastGraphError                = ''
                RequiresRefresh               = $false
                LastRefresh                   = (Get-Date).ToUniversalTime()
            }

            # Add tenant to table
            Add-CIPPAzDataTableEntity @TenantsTable -Entity $NewTenant -Force | Out-Null
            # A cloud marker cached before this row existed would route the tenant's tokens and API hosts
            # to the partner cloud for up to 15 minutes (redanthrax/CIPP#2, #3); drop it.
            $null = Clear-CippTokenCache -TenantFilter $tenantId
            Write-LogMessage -tenant $defaultDomainName -tenantid $tenantId -API 'NewTenant' -message "Added tenant $displayName ($defaultDomainName) with Direct Tenant status ($CloudEnvironment)." -Sev 'Info'

            if ($CloudEnvironment -cne 'Commercial') {
                # The permission push grants permissions to the SAM app over commercial Graph hosts; it
                # neither knows the Azure Government app nor routes government hosts yet (#3). The
                # government app's permissions come from the admin consent given at sign-in.
                Write-LogMessage -tenant $defaultDomainName -tenantid $tenantId -API 'NewTenant' -message "Skipped the permission push for $displayName ($CloudEnvironment): not supported for government tenants yet. The Azure Government app uses the permissions consented at sign-in." -Sev 'Info'
                $Results = @{'message' = "Successfully added tenant $displayName ($defaultDomainName) to the tenant list with Direct Tenant status ($CloudEnvironment)."; 'severity' = 'success' }
                return ([HttpResponseContext]@{
                        StatusCode = $StatusCode
                        Body       = $Results
                    })
            }
            $Results = @{'message' = "Successfully added tenant $displayName ($defaultDomainName) to the tenant list with Direct Tenant status. Permission refresh queued, the tenant will be available shortly."; 'severity' = 'success' }

            # Trigger CPV refresh to push remaining permissions to this specific tenant
            try {
                $Queue = New-CippQueueEntry -Name "Update Permissions - $displayName" -TotalTasks 1
                $TenantBatch = @([PSCustomObject]@{
                        defaultDomainName = $defaultDomainName
                        customerId        = $tenantId
                        displayName       = $displayName
                        FunctionName      = 'UpdatePermissionsQueue'
                        QueueId           = $Queue.RowKey
                    })
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'UpdatePermissionsOrchestrator'
                    Batch            = @($TenantBatch)
                }
                Start-CIPPOrchestrator -InputObject $InputObject
                Write-Information "Started permissions update orchestrator for $displayName"
            } catch {
                Write-Warning "Failed to start permissions orchestrator: $($_.Exception.Message)"
            }

        }
    } catch {
        $Results = @{'message' = "Failed to add tenant: $($_.Exception.Message)"; 'state' = 'error'; 'severity' = 'error' }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}

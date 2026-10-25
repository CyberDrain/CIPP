function Invoke-AddAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {

        $Conditions = $Request.Body.conditions
        Write-Information "Received request to add alert with conditions: $($Conditions | ConvertTo-Json -Compress -Depth 10)"

        # Validate conditions to prevent code injection via operator/property fields
        $AllowedOperators = @('eq', 'ne', 'like', 'notlike', 'match', 'notmatch', 'gt', 'lt', 'ge', 'le', 'in', 'notin', 'contains', 'notcontains', 'between', 'notbetween')
        $SafePropertyRegex = [regex]'^[a-zA-Z0-9_.]+$'
        foreach ($condition in $Conditions) {
            if ($condition.Operator.value -and $condition.Operator.value.ToLower() -notin $AllowedOperators) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ error = "Invalid operator: $($condition.Operator.value)" }
                    })
            }
            if ([string]$condition.Operator.value -in 'between', 'notbetween' -and [string]$condition.Input.value -notmatch '^([01]\d|2[0-3]):[0-5]\d-([01]\d|2[0-3]):[0-5]\d$') {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ error = "A time window needs a start and end time in UTC, such as 07:00-19:00, not '$($condition.Input.value)'." }
                    })
            }
            if ($condition.Property.label -and -not $SafePropertyRegex.IsMatch($condition.Property.label)) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ error = "Invalid property name: $($condition.Property.label)" }
                    })
            }
        }
        # The alert matches when every condition of any one group matches; conditions without a Group are group 0.
        $Groups = @(Split-CIPPAuditLogConditions -Conditions $Conditions)
        foreach ($Group in $Groups) {
            # A record has one Operation, so a second Operation condition in a group could only narrow or contradict the first.
            if (@($Group.Conditions).Where({ [string]$_.Property.label -eq 'Operation' }).Count -gt 1) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ error = 'Each group of conditions can have only one Operation condition. Use In to list several operations.' }
                    })
            }
            $Anchor = Get-CIPPAuditLogRuleAnchor -Conditions $Group.Conditions
            if ($null -eq $Anchor) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ error = $(if ($Groups.Count -gt 1) { 'Each group of conditions needs an Operation condition using Equals, In, or Like with at least three characters of text.' } else { 'An audit log alert needs an Operation condition using Equals, In, or Like with at least three characters of text.' }) }
                    })
            }
        }
        # The log the alert reads: one of the Management Activity API content types.
        $LogType = [string]$Request.Body.logbook.value
        if ($LogType -notin @('Audit.AzureActiveDirectory', 'Audit.Exchange', 'Audit.SharePoint', 'Audit.General')) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ error = "Unknown log source: $LogType" }
                })
        }
        $Threshold = $null
        # Alert when one identity's matching records reach Count within Minutes, instead of on every record.
        if ([bool]$Request.Body.thresholdEnabled) {
            $Count = $Request.Body.threshold.Count -as [int]
            $Minutes = $Request.Body.threshold.Minutes -as [int]
            if ($Count -lt 2 -or $Count -gt 100000 -or $Minutes -lt 10 -or $Minutes -gt 1440) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ error = 'A threshold needs a count from 2 to 100000 and a window from 10 to 1440 minutes.' }
                    })
            }
            if ($Groups.Count -gt 1) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ error = 'A repeated activity alert counts one set of operations, so it cannot have more than one group of conditions.' }
                    })
            }
            if ($Anchor.Patterns.Count -gt 0) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ error = 'A threshold alert counts exact operations, so its Operation condition must use Equals or In, not Like.' }
                    })
            }
            # Only operations where many in a short time means something (Config/AuditLogRepeatedActivityOperations.json).
            $Allowed = (Get-Content -Raw -Path (Join-Path $env:CIPPRootPath 'Config/AuditLogRepeatedActivityOperations.json') | ConvertFrom-Json).$LogType
            $NotAllowed = @(foreach ($Literal in $Anchor.Literals) { if (@($Allowed).Where({ $_ -eq $Literal }, 'First').Count -eq 0) { $Literal } })
            if ($NotAllowed.Count -gt 0) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ error = "A repeated activity alert can't count $($NotAllowed -join ', '). It counts operations such as deletions, downloads, sharing and failed sign-ins, where many in a short time means something." }
                    })
            }
            $Threshold = [string](ConvertTo-Json -Compress -InputObject ([ordered]@{ Count = $Count; Minutes = $Minutes }))
        }

        $Tenants = $Request.Body.tenantFilter
        $Conditions = $Request.Body.conditions | ConvertTo-Json -Compress -Depth 10 | Out-String
        $TenantsJson = $Tenants | ConvertTo-Json -Compress -Depth 10 | Out-String
        $excludedTenantsJson = $Request.Body.excludedTenants | ConvertTo-Json -Compress -Depth 10 | Out-String
        $Actions = $Request.Body.actions | ConvertTo-Json -Compress -Depth 10 | Out-String
        # Which containment actions the 'becremediate' action runs (ListBECRemediationActions ids); empty = the default six.
        $BecActions = @($Request.Body.becActions | ForEach-Object { if ($_ -and $_.PSObject.Properties['value']) { $_.value } else { $_ } } | Where-Object { $_ })
        $RowKey = $Request.Body.RowKey ? $Request.Body.RowKey : (New-Guid).ToString()
        $CompleteObject = @{
            Tenants           = [string]$TenantsJson
            excludedTenants   = [string]$excludedTenantsJson
            Conditions        = [string]$Conditions
            Actions           = [string]$Actions
            BecActions        = [string](ConvertTo-Json -InputObject $BecActions -Compress -Depth 5)
            type              = $LogType
            Threshold         = $Threshold
            RowKey            = $RowKey
            PartitionKey      = 'Webhookv2'
            AlertComment      = [string]$Request.Body.AlertComment
            CustomSubject     = [string]$Request.Body.CustomSubject
            # The audit form posts the raw form values, so an autocomplete selection arrives as a
            # {label, value} object - unwrap it to the bare Halo priority id before storing.
            PsaTicketPriority = [string]($Request.Body.PsaTicketPriority.value ?? $Request.Body.PsaTicketPriority)
        }
        $WebhookTable = Get-CippTable -TableName 'WebhookRules'
        if ($Request.Body.RowKey) {
            # Editing replaces the entity, so carry the disabled state over to keep a disabled alert disabled
            $ExistingAlert = Get-CIPPAzDataTableEntity @WebhookTable -Filter "RowKey eq '$RowKey'" -Property RowKey, Disabled
            if ($ExistingAlert.Disabled -eq $true) {
                $CompleteObject.Disabled = $true
            }
        }
        Add-CIPPAzDataTableEntity @WebhookTable -Entity $CompleteObject -Force
        $Results = "Added Audit Log Alert for $($Tenants.count) tenants. It may take up to four hours before Microsoft starts delivering these alerts."
        Write-LogMessage -API 'AddAlert' -message $Results -sev Info -LogData $CompleteObject -headers $Request.Headers

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ 'Results' = @($Results) }
            })
    } catch {
        Write-LogMessage -API 'AddAlert' -message "Error adding alert: $_" -sev Error -headers $Request.Headers
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ error = "Failed to add alert: $_" }
            })
    }
}

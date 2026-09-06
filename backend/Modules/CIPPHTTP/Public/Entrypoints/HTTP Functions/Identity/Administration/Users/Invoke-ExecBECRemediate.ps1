function Invoke-ExecBECRemediate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    .SYNOPSIS
        Runs selectable Business Email Compromise containment for a user.
    .DESCRIPTION
        Runs the selected containment actions (see ListBECRemediationActions) for a user. With no Actions the original six steps run: reset password, block sign-in, revoke sessions, remove MFA methods, disable inbox rules, disable OneDrive sharing. Actions marked Critical require Confirmation to equal the user's UPN. Pass CaseId to resolve default targets (flagged consents, delegations, rules, devices) from that BEC run and to record the outcome on it; Parameters carries explicit per-action targets (MfaMethodIds, GrantIds, AppRoleAssignmentIds, ServicePrincipalIds, RuleIds, Delegations, TransportRuleIds, AddInIds, Protocols, MobileDeviceIds, RegisteredDeviceIds, CAPolicy).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Body.tenantFilter
    $SuspectUser = $Request.Body.userid
    $Username = $Request.Body.username
    # Action ids from ListBECRemediationActions; empty runs the default six
    $Actions = @($Request.Body.Actions | ForEach-Object { if ($_ -and $_.PSObject.Properties['value']) { $_.value } else { $_ } } | Where-Object { $_ })
    # must equal the user's UPN when a Critical action is selected
    $Confirmation = [string]$Request.Body.Confirmation
    # the BEC run whose findings supply default targets and which records the outcome
    $CaseId = [string]$Request.Body.CaseId
    $Parameters = $Request.Body.Parameters

    $StatusCode = [HttpStatusCode]::OK
    $Results = try {
        if (-not $TenantFilter) { throw 'tenantFilter is required' }
        if (-not $Username) {
            if (-not $SuspectUser) { throw 'username or userid is required' }
            $Username = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$SuspectUser?`$select=userPrincipalName" -tenantid $TenantFilter -AsApp $true).userPrincipalName
        }

        $Catalog = Get-CIPPBecContainmentActions
        $Selected = if ($Actions.Count -eq 0) { @($Catalog | Where-Object { $_.DefaultSelected }) } else { @($Catalog | Where-Object { $_.Id -in $Actions }) }
        $Unknown = @($Actions | Where-Object { $_ -notin $Catalog.Id })
        if ($Unknown.Count -gt 0) { throw "Unknown containment action(s): $($Unknown -join ', ')" }
        $Critical = @($Selected | Where-Object { $_.Impact -eq 'Critical' })
        $ConfirmationOk = $Confirmation -and ($Confirmation.Trim() -ieq ([string]$Username).Trim())
        if ($Critical.Count -gt 0 -and -not $ConfirmationOk) {
            $StatusCode = [HttpStatusCode]::BadRequest
            throw "Type the user's UPN ($Username) to confirm: the selected actions include Critical changes ($($Critical.Label -join ', '))"
        }

        $RunResults = $null
        if ($CaseId) {
            try {
                $Run = Get-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId -IncludeResults
                $RunResults = $Run.Results
            } catch {
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "BEC run $CaseId could not be loaded for target resolution: $($_.Exception.Message)" -Sev 'Warning'
            }
        }

        $Rows = Invoke-CIPPBecContainment -TenantFilter $TenantFilter -UserId $SuspectUser -UserPrincipalName $Username -Actions $Actions -Parameters $Parameters -Confirmed:$ConfirmationOk -CaseId $CaseId -RunResults $RunResults -Headers $Headers -APIName $APIName
        @($Rows | ForEach-Object {
                $Row = [ordered]@{ resultText = $_.resultText; state = $_.state; Action = $_.Action; Target = $_.Target }
                if ($_.copyField) { $Row.copyField = $_.copyField }
                [pscustomobject]$Row
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        if ($StatusCode -eq [HttpStatusCode]::OK) { $StatusCode = [HttpStatusCode]::InternalServerError }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "BEC containment for $Username was not executed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        @([pscustomobject]@{ resultText = $ErrorMessage.NormalizedError; state = 'error' })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = [pscustomobject]@{ Results = @($Results) }
        })
}

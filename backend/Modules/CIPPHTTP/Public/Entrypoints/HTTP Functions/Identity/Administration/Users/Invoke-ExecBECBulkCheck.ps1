function Invoke-ExecBECBulkCheck {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .SYNOPSIS
        Queues Business Email Compromise investigations for many users at once.
    .DESCRIPTION
        Queues one BEC investigation per user as a single orchestration with a queue entry for progress. Accepts either an array of { UserIds, tenantFilter } items (the Users table bulk action) or one object with UserIds[]. Selection=ForeignSuccessfulSignIns picks every user with a successful sign-in in the last 7 days from outside their usage location instead of an explicit list. Each run gets its own case id; results appear on the BEC Reports page and each user's Compromise Remediation tab.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $Entries = @($Request.Body | Where-Object { $_ })
        if ($Entries.Count -eq 0) { throw 'No request body' }
        $Unwrap = { param($Value) if ($Value -and $Value.PSObject.Properties['value']) { $Value.value } else { $Value } }
        $TenantFilter = [string](& $Unwrap ($Entries | ForEach-Object { $_.tenantFilter } | Where-Object { $_ } | Select-Object -First 1))
        if (-not $TenantFilter) { throw 'tenantFilter is required' }
        # explicit ids, or Selection=ForeignSuccessfulSignIns
        $Selection = [string](& $Unwrap ($Entries | ForEach-Object { $_.Selection } | Where-Object { $_ } | Select-Object -First 1))
        $UserIds = @($Entries | ForEach-Object { @($_.UserIds) + @($_.userId) + @($_.userid) } | Where-Object { $_ } | ForEach-Object { [string](& $Unwrap $_) } | Where-Object { $_ } | Select-Object -Unique)

        $Incomplete = $false
        if ($Selection -eq 'ForeignSuccessfulSignIns') {
            $Start = (Get-Date).ToUniversalTime().AddDays(-7).ToString('yyyy-MM-ddTHH:mm:ssZ')
            $Users = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$select=id,userPrincipalName,usageLocation&`$top=999" -tenantid $TenantFilter -AsApp $true)
            $UsageByUser = @{}
            foreach ($User in $Users) { if ($User.id) { $UsageByUser[[string]$User.id] = [string]$User.usageLocation } }
            $SignIns = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=createdDateTime ge $Start and status/errorCode eq 0&`$top=999&`$select=userId,location" -tenantid $TenantFilter -AsApp $true -noPagination $true)
            if ($SignIns.Count -ge 999) { $Incomplete = $true }
            $UserIds = @($SignIns | Where-Object {
                    $Usage = $UsageByUser[[string]$_.userId]
                    $Country = [string]$_.location.countryOrRegion
                    $Usage -and $Country -and $Country -ne 'Unknown' -and $Country -ne $Usage
                } | ForEach-Object { [string]$_.userId } | Select-Object -Unique)
        }
        if ($UserIds.Count -eq 0) { throw 'No users to check' }

        # Resolve UPN and display name in chunks of 15 ids
        $Resolved = @{}
        $Requests = for ($i = 0; $i -lt $UserIds.Count; $i += 15) {
            $Chunk = $UserIds[$i..([Math]::Min($i + 14, $UserIds.Count - 1))]
            @{ id = "u$i"; method = 'GET'; url = "users?`$filter=id in ('$($Chunk -join "','")')&`$select=id,userPrincipalName,displayName" }
        }
        foreach ($Response in @(New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -asapp $true)) {
            foreach ($User in @($Response.body.value)) { if ($User.id) { $Resolved[[string]$User.id] = $User } }
        }

        $RequestedBy = try { ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails } catch { 'CIPP' }
        $Queue = New-CippQueueEntry -Name "BEC investigation - $TenantFilter" -Link "/identity/reports/bec-reports?tenantFilter=$TenantFilter" -Reference "bec-$TenantFilter-$([guid]::NewGuid().ToString('N'))" -TotalTasks $UserIds.Count
        $Batch = [System.Collections.Generic.List[object]]::new()
        $Cases = [System.Collections.Generic.List[object]]::new()
        foreach ($UserId in $UserIds) {
            $User = $Resolved[$UserId]
            if (-not $User) {
                $Cases.Add([pscustomobject]@{ UserId = $UserId; UserPrincipalName = $null; CaseId = $null; Error = 'User not found' })
                continue
            }
            $Prepared = New-CIPPBecRunRequest -TenantFilter $TenantFilter -UserId ([string]$User.id) -UserPrincipalName ([string]$User.userPrincipalName) -DisplayName ([string]$User.displayName) -RequestedBy ([string]$RequestedBy) -QueueId ([string]$Queue.RowKey)
            $Batch.Add($Prepared.Item)
            $Cases.Add([pscustomobject]@{ UserId = [string]$User.id; UserPrincipalName = [string]$User.userPrincipalName; CaseId = $Prepared.CaseId })
        }
        if ($Batch.Count -eq 0) { throw 'None of the selected users could be resolved' }
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'BECRunOrchestrator'
            Batch            = @($Batch)
            SkipLog          = $true
        }
        $null = Start-CIPPOrchestrator -InputObject $InputObject
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Queued $($Batch.Count) BEC investigation(s) (queue $($Queue.RowKey))" -Sev 'Info'
        $Body = @{
            Results = "Queued $($Batch.Count) BEC investigation(s). Results appear on the BEC Reports page and each user's Compromise Remediation tab.$(if ($Incomplete) { ' The foreign sign-in selection hit its cap; some users may be missing.' })"
            QueueId = $Queue.RowKey
            Cases   = @($Cases)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Bulk BEC investigation not queued: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Bulk BEC investigation not queued: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

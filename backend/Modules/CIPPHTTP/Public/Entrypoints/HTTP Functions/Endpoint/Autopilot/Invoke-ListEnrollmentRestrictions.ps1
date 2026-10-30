function Invoke-ListEnrollmentRestrictions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.Read
    .DESCRIPTION
        Lists a tenant's enrollment (device type) restrictions for specific groups, one row per restriction as the Intune portal shows them: the two objects behind an Android restriction are combined. Each row carries the flat settings the add, edit and template forms use, its priority, and its assignment (AssignTo, customGroup and the readable PolicyAssignment). The tenant's default restriction is managed by the DefaultPlatformRestrictions standard and is not listed.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    try {
        # Graph's groupAssignmentTarget carries only groupId, so fetch group names in the same batch
        # and resolve them into PolicyAssignment like the Autopilot profile and MEM policy lists do.
        $BulkRequests = @(
            [PSCustomObject]@{ id = 'Configurations'; method = 'GET'; url = '/deviceManagement/deviceEnrollmentConfigurations?$top=999&$expand=assignments' }
            [PSCustomObject]@{ id = 'Groups'; method = 'GET'; url = '/groups?$top=999&$select=id,displayName' }
        )
        $BulkResults = New-GraphBulkRequest -Requests $BulkRequests -tenantid $TenantFilter

        $GroupLookup = @{}
        $GroupResult = $BulkResults | Where-Object { $_.id -eq 'Groups' } | Select-Object -First 1
        foreach ($Group in @($GroupResult.body.value)) {
            if ($Group.id) { $GroupLookup[$Group.id] = $Group.displayName }
        }

        $ConfigurationResult = $BulkResults | Where-Object { $_.id -eq 'Configurations' } | Select-Object -First 1
        if ($null -ne $ConfigurationResult.status -and ($ConfigurationResult.status -lt 200 -or $ConfigurationResult.status -ge 300)) {
            throw ($ConfigurationResult.body.error.message ?? "Graph returned status $($ConfigurationResult.status) listing enrollment restrictions")
        }
        $Configurations = @($ConfigurationResult.body.value | Where-Object { $_ })
        $AssignmentText = @{}
        foreach ($Configuration in $Configurations) {
            $ListItem = ConvertTo-CIPPIntunePolicyListItem -Policy $Configuration -URLName 'deviceEnrollmentConfigurations' -DefaultPolicyTypeName 'Enrollment Restriction' -GroupLookup $GroupLookup
            $AssignmentText["$($Configuration.id)"] = $ListItem.PolicyAssignment
        }

        $PlatformLabels = @{ android = 'Android'; ios = 'iOS/iPadOS'; macOS = 'macOS'; windows = 'Windows' }
        $Results = foreach ($Restriction in @(ConvertFrom-CIPPEnrollmentRestrictionConfiguration -Configurations $Configurations -GroupNameById $GroupLookup)) {
            $Restriction | Add-Member -NotePropertyMembers ([ordered]@{
                    id               = $Restriction.ids[0]
                    platformLabel    = $PlatformLabels[$Restriction.platform]
                    PolicyAssignment = $AssignmentText[$Restriction.ids[0]]
                }) -Force
            $Restriction
        }
        $Results = @($Results | Sort-Object -Property platform, priority, displayName)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to list enrollment restrictions: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })
}

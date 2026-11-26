function ConvertFrom-CIPPLicenseAuditEvent {
    <#
    .SYNOPSIS
        Turns 'Change user license' directory audit events into one row per licence added to or removed from a user.
    .DESCRIPTION
        Entra writes a licence change's old and new AssignedLicense lists into additionalDetails, split into ~10 KB
        chunks that are each their own audit event and share an 'id', with 'seq' (1-based) and 'c' (chunk count).
        The chunks are joined back per id and dropped as soon as a change is complete; a change missing a chunk
        (cut off by the lookback window) or with an unreadable chunk is skipped. Events that carry the lists in
        modifiedProperties instead are read from there. SKUs only in the new list are Added, SKUs only in the old
        list Removed; a change to disabled service plans alone returns nothing. Failed operations are ignored.
        Entra logs a partner technician as 'user_<id>@<partner domain>'; those are looked up in the partner tenant
        and shown with their real UPN.
    .PARAMETER Events
        Directory audit events (auditLogs/directoryAudits) with initiatedBy, targetResources and additionalDetails.
        Pipe them in (New-GraphGetRequest -Stream) so a month of chunks is never held at once.
    .PARAMETER TenantFilter
        Tenant used to resolve SKU display names the conversion table does not list.
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [object[]]$Events = @(),
        [string]$TenantFilter
    )

    begin {
        $SkuPattern = [regex]'SkuName=(?<name>[^,\]]*),.*?SkuId=(?<id>[0-9a-fA-F-]{36})'
        $Chunked = @{}
        $Rows = [System.Collections.Generic.List[object]]::new()
        $PartnerActors = [System.Collections.Generic.HashSet[string]]::new()
    }

    process {
        foreach ($AuditEvent in $Events) {
            if ($AuditEvent.activityDisplayName -ne 'Change user license') { continue }
            if ($AuditEvent.result -and $AuditEvent.result -ne 'success') { continue }
            $Details = @{}
            foreach ($Detail in $AuditEvent.additionalDetails) { $Details[[string]$Detail.key] = [string]$Detail.value }

            $Changes = [System.Collections.Generic.List[object]]::new()
            if ($Details['id'] -and $Details.ContainsKey('b')) {
                $BlobId = $Details['id']
                $Seq = $Details['seq'] -as [int]
                $Count = $Details['c'] -as [int]
                if (-not $Seq -or -not $Count -or $Seq -lt 1 -or $Seq -gt $Count) { continue }
                $Entry = $Chunked[$BlobId]
                if (-not $Entry) {
                    $Entry = @{ Count = $Count; Parts = [System.Collections.Generic.SortedDictionary[int, string]]::new(); Event = $null }
                    $Chunked[$BlobId] = $Entry
                }
                if ($Count -ne $Entry.Count) { continue }
                $Entry.Parts[$Seq] = $Details['b']
                if ($Seq -eq 1) { $Entry.Event = $AuditEvent }
                if ($Entry.Parts.Count -lt $Entry.Count) { continue }

                $Chunked.Remove($BlobId)
                $Target = $null
                foreach ($Resource in $Entry.Event.targetResources) { if ($Resource.type -eq 'User') { $Target = $Resource; break } }
                try {
                    $Updated = (-join $Entry.Parts.Values | ConvertFrom-Json -ErrorAction Stop).targetUpdatedProperties | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Write-Information "Skipping unreadable licence change $($BlobId): $($_.Exception.Message)"
                    continue
                }
                foreach ($Prop in $Updated) {
                    if ($Prop.Name -eq 'AssignedLicense') {
                        $Changes.Add(@{ Event = $Entry.Event; Target = $Target; Old = @($Prop.OldValue); New = @($Prop.NewValue) })
                        break
                    }
                }
            } else {
                foreach ($Resource in $AuditEvent.targetResources) {
                    foreach ($Prop in $Resource.modifiedProperties) {
                        if ($Prop.displayName -ne 'AssignedLicense') { continue }
                        $Changes.Add(@{
                                Event  = $AuditEvent
                                Target = $Resource
                                Old    = @(if ($Prop.oldValue) { $Prop.oldValue | ConvertFrom-Json })
                                New    = @(if ($Prop.newValue) { $Prop.newValue | ConvertFrom-Json })
                            })
                    }
                }
            }

            foreach ($Change in $Changes) {
                $Old = @{}
                $New = @{}
                foreach ($Value in $Change.Old) { foreach ($Match in $SkuPattern.Matches([string]$Value)) { $Old[$Match.Groups['id'].Value.ToLowerInvariant()] = $Match.Groups['name'].Value } }
                foreach ($Value in $Change.New) { foreach ($Match in $SkuPattern.Matches([string]$Value)) { $New[$Match.Groups['id'].Value.ToLowerInvariant()] = $Match.Groups['name'].Value } }
                $Diff = @(
                    foreach ($SkuId in $New.Keys) { if (-not $Old.ContainsKey($SkuId)) { @{ SkuId = $SkuId; Part = $New[$SkuId]; Change = 'Added' } } }
                    foreach ($SkuId in $Old.Keys) { if (-not $New.ContainsKey($SkuId)) { @{ SkuId = $SkuId; Part = $Old[$SkuId]; Change = 'Removed' } } }
                )
                if ($Diff.Count -eq 0) { continue }

                $Source = $Change.Event
                $Target = $Change.Target
                $App = $Source.initiatedBy.app
                $User = $Source.initiatedBy.user
                $ActorType = if ($User.id -or $User.userPrincipalName) { 'User' } elseif ($App.appId -or $App.servicePrincipalId -or $App.displayName) { 'Application' } else { 'Unknown' }
                $Actor = [string]($User.userPrincipalName ?? $App.displayName ?? $App.appId)
                if ($User.id -and $env:TenantID -and $User.homeTenantId -eq $env:TenantID) { $null = $PartnerActors.Add($User.id) }

                foreach ($Item in $Diff) {
                    $Rows.Add([PSCustomObject]@{
                            id                = "$($Source.id)-$($Target.id)-$($Item.SkuId)"
                            activityDateTime  = $Source.activityDateTime
                            userId            = [string]$Target.id
                            userPrincipalName = [string]$Target.userPrincipalName
                            change            = $Item.Change
                            license           = $Item.Part
                            skuPartNumber     = $Item.Part
                            skuId             = $Item.SkuId
                            initiatedByType   = $ActorType
                            initiatedBy       = $Actor
                            initiatedById     = [string]($User.id ?? $App.servicePrincipalId)
                        })
                }
            }
        }
    }

    end {
        if ($Rows.Count -gt 0) {
            $Names = @{}
            foreach ($Sku in Get-CIPPLicenseSkuName -SkuIds @($Rows.skuId) -TenantFilter $TenantFilter) { $Names[$Sku.skuId] = $Sku.displayName }
            foreach ($Row in $Rows) { if ($Names[$Row.skuId]) { $Row.license = $Names[$Row.skuId] } }
        }

        if ($PartnerActors.Count -gt 0) {
            try {
                $Body = [CIPP.CippJson]::ToJson(@{ ids = @($PartnerActors); types = @('user') }, 3)
                $Upns = @{}
                foreach ($Technician in (New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/directoryObjects/getByIds?$select=id,userPrincipalName' -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true -body $Body).value) {
                    $Upns[$Technician.id] = $Technician.userPrincipalName
                }
                foreach ($Row in $Rows) { if ($Row.initiatedById -and $Upns[$Row.initiatedById]) { $Row.initiatedBy = $Upns[$Row.initiatedById] } }
            } catch {
                Write-Information "Could not resolve partner technicians: $($_.Exception.Message)"
            }
        }

        return $Rows.ToArray()
    }
}

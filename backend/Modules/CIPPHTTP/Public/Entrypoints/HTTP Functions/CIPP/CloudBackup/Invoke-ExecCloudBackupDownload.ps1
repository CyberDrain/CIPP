function Invoke-ExecCloudBackupDownload {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackupRestore.ReadWrite
    .SYNOPSIS
        Download an export zip or a single backed-up item
    .DESCRIPTION
        With JobId, downloads the zip of a completed export that has not expired. With PolicyId, TenantId, Workload, OwnerId and Key, downloads one backed-up item: a mail message as its .eml file, other mailbox items as JSON, files as stored. The data is decrypted by CIPP and sent in parts of up to 16 MB: request Part 0, 1, ... up to X-CIPP-Download-Parts - 1 and join them in order. X-CIPP-Download-Size is the total size in bytes.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Export job id from ExecCloudBackupExport
    $JobId = "$($Request.Query.JobId)"
    $PolicyId = "$($Request.Query.PolicyId)"
    # Tenant of the backup (customerId or default domain)
    $TenantId = "$($Request.Query.TenantId)"
    # exchange, onedrive, sharepoint or teams
    $Workload = "$($Request.Query.Workload)".ToLowerInvariant()
    # Owner id as returned by ListCloudBackupOwners
    $OwnerId = "$($Request.Query.OwnerId)"
    # Item key as returned by ListCloudBackupItems
    $Key = "$($Request.Query.Key)"
    # Storage version of the item as returned by ListCloudBackupItems; the current version when empty
    $VersionId = "$($Request.Query.VersionId)"
    # Item name used for the downloaded file name
    $Name = "$($Request.Query.Name)"
    # Point in time of the item (RunStamp), used to describe mailbox items that have no .eml copy
    $AsOf = "$($Request.Query.AsOf)"
    # Zero-based part number
    $PartText = "$($Request.Query.Part)"

    $Part = 0
    if ($PartText -and -not [int]::TryParse($PartText, [ref]$Part) -or $Part -lt 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Part must be a whole number from 0' } })
    }
    if ($JobId -and -not ($JobId -as [guid])) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'JobId must be a job id (GUID)' } })
    }
    if (-not $JobId) {
        if (-not ($PolicyId -as [guid])) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Give a JobId, or a PolicyId (GUID) with TenantId, Workload, OwnerId and Key' } })
        }
        if (-not $TenantId -or $TenantId -eq 'AllTenants' -or $TenantId -like 'group:*') {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'TenantId must be a single tenant' } })
        }
        if ($Workload -notin @('exchange', 'onedrive', 'sharepoint', 'teams')) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Workload must be exchange, onedrive, sharepoint or teams' } })
        }
        if (-not $OwnerId) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'OwnerId is required' } })
        }
        if (-not $Key -or $Key.StartsWith('/') -or $Key.StartsWith('index/') -or $Key -match '(^|/)\.\.?(/|$)|[\u0000-\u001F\u007F\\]') {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Key must be an item key from ListCloudBackupItems' } })
        }
    }

    try {
        $Lookup = Get-CIPPTenantLookup
        $AllowedTenants = @(Test-CIPPAccess -Request $Request -TenantList)
        $Now = [datetime]::UtcNow

        if ($JobId) {
            $JobsTable = Get-CIPPTable -TableName 'CloudBackupJobs'
            $Job = @(Get-CIPPAzDataTableEntity @JobsTable -Filter "PartitionKey eq 'CloudBackupJob' and RowKey eq '$([guid]$JobId)'")[0]
            if (-not $Job -or $Job.Type -ne 'Export') {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = "Export $JobId was not found" } })
            }
            if ($AllowedTenants -notcontains 'AllTenants' -and $AllowedTenants -notcontains $Job.SourceTenantId) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Forbidden; Body = @{ Results = 'You do not have access to the tenant of this export' } })
            }
            if ($Job.Status -ne 'Completed' -or -not $Job.ExportKey) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'This export has not finished' } })
            }
            if ($Job.ExportRemovedAt -or [string]::CompareOrdinal("$($Job.ExpiresAt)", $Now.ToString('o')) -le 0) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = 'This export has expired. Run the export again.' } })
            }
            $Policy = Get-CIPPCloudBackupPolicy -Id $Job.PolicyId
            $Destination = if ($Policy) { Get-CIPPCloudBackupDestination -Id $Policy.DestinationId -IncludeSecret }
            if (-not $Destination) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = 'The policy or destination of this export no longer exists' } })
            }
            $Download = Read-CIPPCloudBackupObjectPart -Destination $Destination -Key $Job.ExportKey -Part $Part
            if (-not $Download) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = 'The export file was not found in the destination. Run the export again.' } })
            }
            $FileName = "$($Job.SourceOwnerName ?? $Job.SourceOwnerId)-$($Job.Workload)-$($Job.RunStamp).zip"
            $ContentType = 'application/zip'
            $TenantDomain = $Lookup["$($Job.SourceTenantId)"].defaultDomainName ?? $Job.SourceTenant
            $TenantCustomerId = "$($Job.SourceTenantId)"
            $What = "export $JobId of $($Job.SourceOwnerName ?? $Job.SourceOwnerId)"
        } else {
            $Tenant = $Lookup[$TenantId]
            if (-not $Tenant) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = "Tenant $TenantId was not found" } })
            }
            if ($AllowedTenants -notcontains 'AllTenants' -and $AllowedTenants -notcontains $Tenant.customerId) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Forbidden; Body = @{ Results = 'You do not have access to this tenant' } })
            }
            $TenantDomain = $Tenant.defaultDomainName
            $TenantCustomerId = $Tenant.customerId
            $Source = Resolve-CIPPCloudBackupJobSource -PolicyId $PolicyId -TenantId $Tenant.customerId -Workload $Workload -OwnerId $OwnerId -SkipRecoveryPoint
            $Destination = $Source.Destination
            $ItemName = if ($Name) { $Name } else { $Key.Substring($Key.LastIndexOf('/') + 1) }
            $What = "$Workload item '$ItemName' of $($Source.DisplayName)"
            $StorageKey = "$($Source.OwnerPrefix)$Key"
            $StorageVersion = $VersionId
            $ContentType = if ($Key.EndsWith('.json', [System.StringComparison]::OrdinalIgnoreCase)) { 'application/json' } else { 'application/octet-stream' }
            $FileName = $ItemName
            $Json = $null

            if ($Workload -eq 'exchange' -and $Key.EndsWith('.fts', [System.StringComparison]::Ordinal)) {
                $Base = "$($Source.OwnerPrefix)$($Key.Substring(0, $Key.Length - 4))"
                $FtsVersions = [System.Collections.Generic.List[object]]::new()
                $EmlVersions = [System.Collections.Generic.List[object]]::new()
                foreach ($Version in @(Get-CIPPCloudBackupObjectVersionList -Destination $Destination -Prefix "$Base.")) {
                    if ($null -eq $Version -or $Version.IsDeleteMarker) { continue }
                    if ($Version.Key -ceq "$Base.fts") { $FtsVersions.Add($Version) } elseif ($Version.Key -ceq "$Base.eml") { $EmlVersions.Add($Version) }
                }
                $Fts = $null
                foreach ($Version in $FtsVersions) {
                    if (($VersionId -and $Version.VersionId -ceq $VersionId) -or (-not $VersionId -and $Version.IsLatest)) { $Fts = $Version; break }
                }
                $Eml = $null
                if ($Fts) {
                    $From = [datetime]$Fts.LastModified
                    $Until = $null
                    foreach ($Version in $FtsVersions) {
                        $When = [datetime]$Version.LastModified
                        if ($When -gt $From -and ($null -eq $Until -or $When -lt $Until)) { $Until = $When }
                    }
                    foreach ($Version in $EmlVersions) {
                        $When = [datetime]$Version.LastModified
                        if ($When -ge $From -and ($null -eq $Until -or $When -lt $Until) -and ($null -eq $Eml -or $When -lt [datetime]$Eml.LastModified)) { $Eml = $Version }
                    }
                }
                if ($Eml) {
                    $StorageKey = $Eml.Key
                    $StorageVersion = $Eml.VersionId
                    $ContentType = 'message/rfc822'
                    $FileName = "$ItemName.eml"
                } else {
                    $Entry = $null
                    foreach ($Candidate in @(Get-CIPPCloudBackupOwnerListing -Destination $Destination -OwnerPrefix $Source.OwnerPrefix -AsOf $(if ($AsOf) { $AsOf } else { $Now.ToString('yyyyMMddTHHmmssZ') }) -Key @($Key) -IncludeDeleted -Stream)) {
                        if ($null -ne $Candidate -and $Candidate.Key -ceq $Key) { $Entry = $Candidate; break }
                    }
                    if (-not $Entry) {
                        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = 'This item was not found in the backup at that point in time' } })
                    }
                    $Item = [ordered]@{ Name = $Entry.Name; Type = $Entry.Type; Path = $Entry.Path; Size = $Entry.Size; Modified = $Entry.Modified; Details = $Entry.Extra }
                    $Json = [System.Text.Encoding]::UTF8.GetBytes(([CIPP.CippJson]::ToJson($Item, 10) ?? (ConvertTo-Json -InputObject $Item -Depth 10)))
                    $ContentType = 'application/json'
                    $FileName = "$ItemName.json"
                }
            }

            $Download = if ($Json) {
                if ($Part -gt 0) { throw [System.ArgumentException]::new("Part $Part does not exist; the download has 1 part(s).") }
                [pscustomobject]@{ Body = $Json; Part = 0; Parts = 1; Size = [int64]$Json.Length }
            } else {
                Read-CIPPCloudBackupObjectPart -Destination $Destination -Key $StorageKey -VersionId $StorageVersion -Part $Part
            }
            if (-not $Download) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = 'This version of the item was not found in the destination' } })
            }
        }

        if ($Part -eq 0) {
            Write-LogMessage -headers $Request.Headers -API 'CloudBackupRestore' -tenant $TenantDomain -tenantid $TenantCustomerId -message "Downloaded $What ($($Download.Size) bytes)" -sev Info
        }
        $SafeName = ($FileName -replace '[\u0000-\u001F\u007F"\\/:*?<>|]', '_').Trim()
        if (-not $SafeName) { $SafeName = 'download' }
        $AsciiName = $SafeName -replace '[^ -~]', '_'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = $ContentType
                Headers     = @{
                    'Content-Disposition'   = "attachment; filename=`"$AsciiName`"; filename*=UTF-8''$([uri]::EscapeDataString($SafeName))"
                    'Cache-Control'         = 'no-store'
                    'X-CIPP-Download-Part'  = "$($Download.Part)"
                    'X-CIPP-Download-Parts' = "$($Download.Parts)"
                    'X-CIPP-Download-Size'  = "$($Download.Size)"
                }
                Body        = [byte[]]$Download.Body
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to download from the cloud backup: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Request.Headers -API 'CloudBackupRestore' -message $Result -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = @{ Results = $Result }
            })
    }
}

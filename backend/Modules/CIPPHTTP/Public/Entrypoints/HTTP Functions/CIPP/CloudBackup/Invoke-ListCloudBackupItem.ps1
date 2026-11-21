function Invoke-ListCloudBackupItem {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackup.Read
    .SYNOPSIS
        Show one backed-up item at a point in time with its stored versions
    .DESCRIPTION
        Returns one item of a backed-up mailbox, OneDrive, site, team or chat user as it was at a recovery point (the latest when AsOf is not given), including whether it was deleted by then, and every stored version of it (VersionId, time, size, whether the version marks a deletion), newest first. Callers limited to some tenants can only read those tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Cloud backup policy id
    $PolicyId = "$($Request.Query.PolicyId)"
    # Tenant customerId or default domain
    $TenantValue = "$($Request.Query.TenantId)"
    # Workload: exchange, onedrive, sharepoint or teams
    $Workload = "$($Request.Query.Workload)".ToLowerInvariant()
    # Owner id as returned by ListCloudBackupOwners
    $OwnerId = "$($Request.Query.OwnerId)"
    # Item key as returned by ListCloudBackupItems
    $Key = "$($Request.Query.Key)"
    # RunStamp from ListCloudBackupRecoveryPoints, or a date and time; the latest recovery point when empty
    $AsOfValue = "$($Request.Query.AsOf)"

    if (-not ($PolicyId -as [guid])) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'PolicyId must be a policy id (GUID)' }
            })
    }
    if (-not $TenantValue) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'TenantId is required' }
            })
    }
    if ($Workload -notin @('exchange', 'onedrive', 'sharepoint', 'teams')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Workload must be exchange, onedrive, sharepoint or teams' }
            })
    }
    if (-not $OwnerId) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'OwnerId is required' }
            })
    }
    if (-not $Key) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Key is required' }
            })
    }
    $AsOf = [datetime]::UtcNow
    if ($AsOfValue -match '^\d{8}T\d{6}Z$') {
        $AsOf = $AsOfValue
    } elseif ($AsOfValue) {
        $Parsed = [datetimeoffset]::MinValue
        if (-not [datetimeoffset]::TryParse($AsOfValue, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = 'AsOf must be a recovery point (RunStamp) or a date and time' }
                })
        }
        $AsOf = $Parsed.UtcDateTime
    }

    try {
        $TenantId = (Get-CIPPTenantLookup)[$TenantValue].customerId
        if (-not $TenantId) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Results = "Tenant $TenantValue was not found" }
                })
        }
        $AllowedTenants = @(Test-CIPPAccess -Request $Request -TenantList)
        if ($AllowedTenants -notcontains 'AllTenants' -and $AllowedTenants -notcontains $TenantId) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = @{ Results = 'You do not have access to this tenant' }
                })
        }

        $Source = Get-CIPPCloudBackupOwnerSource -PolicyId $PolicyId -TenantId $TenantId -Workload $Workload -OwnerId $OwnerId
        $Listing = Get-CIPPCloudBackupOwnerListing -Destination $Source.Destination -OwnerPrefix $Source.OwnerPrefix -AsOf $AsOf -Key @($Key) -IncludeDeleted -IncludeFolders -Take 1
        $Found = $null
        foreach ($Entry in @($Listing.Items)) { if ($Entry.Key -ceq $Key) { $Found = $Entry; break } }
        if (-not $Found) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Results = 'This item is not in the backup at that point in time' }
                })
        }

        $Versions = @()
        if ($Found.Type -ne 'folder') {
            $FullKey = "$($Source.OwnerPrefix)$Key"
            $Matching = foreach ($Version in @(Get-CIPPCloudBackupObjectVersionList -Destination $Source.Destination -Prefix $FullKey)) {
                if ($Version.Key -cne $FullKey) { continue }
                [pscustomobject]@{
                    VersionId = "$($Version.VersionId)"
                    At        = if ($Version.LastModified -is [datetime]) { $Version.LastModified.ToUniversalTime().ToString('o') } else { "$($Version.LastModified)" }
                    Size      = [int64]($Version.Size -as [int64])
                    Deleted   = [bool]$Version.IsDeleteMarker
                }
            }
            $Versions = @($Matching | Sort-Object -Property At -Descending)
        }

        $Body = [pscustomobject]@{
            RunStamp  = "$($Listing.RunStamp)"
            Key       = $Found.Key
            Path      = $Found.Path
            Name      = $Found.Name
            Type      = $Found.Type
            Size      = $Found.Size
            Modified  = $Found.Modified
            VersionId = $Found.VersionId
            Deleted   = [bool]$Found.Deleted
            Extra     = $Found.Extra
            Versions  = $Versions
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to read the cloud backup item: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = @{ Results = "Failed to read the cloud backup item: $($ErrorMessage.NormalizedError)" }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

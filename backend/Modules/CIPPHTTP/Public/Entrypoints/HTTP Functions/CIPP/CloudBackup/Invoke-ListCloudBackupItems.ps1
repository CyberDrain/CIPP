function Invoke-ListCloudBackupItems {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackup.Read
    .SYNOPSIS
        Browse or search the backed-up items of a mailbox, OneDrive, site, team or chat user at a point in time
    .DESCRIPTION
        Returns { RunStamp, Total, Items, Folders }: the items and subfolders of one folder of a backed-up mailbox, OneDrive, site, team or chat user as they were at a recovery point (the latest when AsOf is not given). Search matches names, paths, subjects and senders, and with DateFrom/DateTo covers the whole folder tree below Path (the whole owner without Path); Type limits the item types. Paged with Skip and Take (at most 500). Callers limited to some tenants can only browse those tenants.
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
    # RunStamp from ListCloudBackupRecoveryPoints, or a date and time; the latest recovery point when empty
    $AsOfValue = "$($Request.Query.AsOf)"
    # Folder path to list, with / separators; the top level when empty
    $Path = "$($Request.Query.Path)"
    # Text to find in item names, paths, subjects and senders
    $Search = "$($Request.Query.Search)"
    # Comma-separated item types, for example message,event,contact,file,folder,chatMessage,channelMessage
    $Type = "$($Request.Query.Type)"
    # Only items modified on or after this date and time
    $DateFromValue = "$($Request.Query.DateFrom)"
    # Only items modified on or before this date and time
    $DateToValue = "$($Request.Query.DateTo)"
    # Number of items to skip
    $Skip = if ("$($Request.Query.Skip)") { $Request.Query.Skip -as [int] } else { 0 }
    # Number of items to return, 1 to 500 (default 100)
    $Take = if ("$($Request.Query.Take)") { $Request.Query.Take -as [int] } else { 100 }

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
    if ($null -eq $Skip -or $Skip -lt 0 -or $null -eq $Take -or $Take -lt 1 -or $Take -gt 500) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Skip must be 0 or more and Take between 1 and 500' }
            })
    }
    $DateFrom = [datetimeoffset]::MinValue
    $DateTo = [datetimeoffset]::MinValue
    if (($DateFromValue -and -not [datetimeoffset]::TryParse($DateFromValue, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$DateFrom)) -or
        ($DateToValue -and -not [datetimeoffset]::TryParse($DateToValue, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$DateTo))) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'DateFrom and DateTo must be dates and times' }
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
        $ListingParams = @{
            Destination = $Source.Destination
            OwnerPrefix = $Source.OwnerPrefix
            AsOf        = $AsOf
            Skip        = $Skip
            Take        = $Take
        }
        if ($Path -or -not ($Search -or $DateFromValue -or $DateToValue)) { $ListingParams.Path = $Path }
        if ($Search) { $ListingParams.Search = $Search }
        if ($DateFromValue) { $ListingParams.ModifiedFrom = $DateFrom.UtcDateTime }
        if ($DateToValue) { $ListingParams.ModifiedTo = $DateTo.UtcDateTime }
        if ($Path -and ($Search -or $DateFromValue -or $DateToValue)) { $ListingParams.Recurse = $true }
        if ($Type) { $ListingParams.Type = [string[]]@(foreach ($Name in $Type.Split(',')) { if ($Name.Trim()) { $Name.Trim() } }) }
        $Listing = Get-CIPPCloudBackupOwnerListing @ListingParams
        if (-not $Listing.RunStamp) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Results = 'There is no backup of this owner at that point in time' }
                })
        }

        $Body = [pscustomobject]@{
            RunStamp = "$($Listing.RunStamp)"
            Total    = [int]$Listing.Total
            Items    = @(foreach ($Entry in @($Listing.Items)) {
                    [pscustomobject]@{
                        Key       = $Entry.Key
                        Path      = $Entry.Path
                        Name      = $Entry.Name
                        Type      = $Entry.Type
                        Size      = $Entry.Size
                        Modified  = $Entry.Modified
                        VersionId = $Entry.VersionId
                        Extra     = $Entry.Extra
                    }
                })
            Folders  = @(foreach ($Folder in @($Listing.Folders)) {
                    [pscustomobject]@{
                        Key  = $Folder.Key
                        Path = $Folder.Path
                        Name = $Folder.Name
                    }
                })
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to list cloud backup items: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = @{ Results = "Failed to list cloud backup items: $($ErrorMessage.NormalizedError)" }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

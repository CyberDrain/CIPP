function Save-CIPPCloudBackupExchangeItem {
    <#
    .SYNOPSIS
        Exports mailbox items to the backup destination (.fts, plus .eml for mail messages) and builds their index entries.
    .DESCRIPTION
        Items are { Id; Class; Size; Created; Modified; Attempts } from the mailbox item delta. Returns
        { Items; Bytes; Warnings; IndexEntries; Failed }, where Failed holds the items to retry on the next run.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context,

        [Parameter(Mandatory = $true)]
        [string]$MailboxId,

        [Parameter(Mandatory = $true)]
        [string]$FolderKey,

        [string]$FolderPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Items
    )

    $BatchBytes = 24MB
    $Tenant = $Context.TenantFilter
    $Owner = $Context.OwnerId
    $Warnings = [System.Collections.Generic.List[string]]::new()
    $IndexEntries = [System.Collections.Generic.List[object]]::new()
    $Failed = [System.Collections.Generic.List[object]]::new()
    $Saved = 0
    $Bytes = [long]0

    # At most 4 requests per $batch (the per-mailbox concurrency limit) and $BatchBytes of item data per response.
    $ToBatches = {
        param($Units)
        $Batches = [System.Collections.Generic.List[object]]::new()
        $Current = [System.Collections.Generic.List[object]]::new()
        $Total = [long]0
        foreach ($Unit in $Units) {
            if ($Current.Count -gt 0 -and ($Current.Count -ge 4 -or $Total + $Unit.Size -gt $BatchBytes)) {
                $Batches.Add($Current.ToArray())
                $Current = [System.Collections.Generic.List[object]]::new()
                $Total = 0
            }
            $Current.Add($Unit.Request)
            $Total += $Unit.Size
        }
        if ($Current.Count -gt 0) { $Batches.Add($Current.ToArray()) }
        , $Batches
    }

    $ById = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
    $ExportUnits = [System.Collections.Generic.List[object]]::new()
    $GroupIds = [System.Collections.Generic.List[string]]::new()
    $GroupSize = [long]0
    foreach ($Item in $Items) {
        $Class = [string]$Item.Class
        $Type = if ($Class -like 'IPM.Appointment*') { 'event' } elseif ($Class -like 'IPM.Contact*' -or $Class -like 'IPM.DistList*') { 'contact' } else { 'message' }
        $ItemKey = 'items/{0}/{1}' -f $FolderKey, ([string]$Item.Id).Replace('/', '-').Replace('+', '_')
        $ById[[string]$Item.Id] = @{
            Item      = $Item
            Type      = $Type
            WantsMime = $Class -like 'IPM.Note*' -or $Class -like 'IPM.Schedule.Meeting*'
            Key       = $ItemKey
            Size      = [long]$Item.Size
        }
        if ($GroupIds.Count -gt 0 -and ($GroupIds.Count -ge 20 -or $GroupSize + [long]$Item.Size -gt $BatchBytes)) {
            $ExportUnits.Add(@{ Ids = $GroupIds.ToArray(); Size = $GroupSize })
            $GroupIds = [System.Collections.Generic.List[string]]::new()
            $GroupSize = 0
        }
        $GroupIds.Add([string]$Item.Id)
        $GroupSize += [long]$Item.Size
    }
    if ($GroupIds.Count -gt 0) { $ExportUnits.Add(@{ Ids = $GroupIds.ToArray(); Size = $GroupSize }) }

    # https://learn.microsoft.com/graph/api/mailbox-exportitems?view=graph-rest-beta (max 20 itemIds per request)
    $Units = for ($i = 0; $i -lt $ExportUnits.Count; $i++) {
        @{
            Size    = $ExportUnits[$i].Size
            Request = @{
                id      = "$i"
                method  = 'POST'
                url     = "/admin/exchange/mailboxes/$MailboxId/exportItems"
                body    = @{ itemIds = $ExportUnits[$i].Ids }
                headers = @{ 'Content-Type' = 'application/json' }
            }
        }
    }

    $Exported = [System.Collections.Generic.List[object]]::new()
    foreach ($Batch in (& $ToBatches $Units)) {
        try {
            $Responses = New-GraphBulkRequest -tenantid $Tenant -asapp $true -Requests $Batch
        } catch {
            $Message = $_.Exception.Message
            foreach ($Request in $Batch) {
                foreach ($Id in $Request.body.itemIds) {
                    $Warnings.Add("Export of item $Id failed: $Message")
                    $Failed.Add($ById[$Id].Item)
                }
            }
            continue
        }
        $Answered = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $RequestErrors = @{}
        foreach ($Response in $Responses) {
            if (([int]$Response.status) -ge 400) {
                $RequestErrors[[string]$Response.id] = "HTTP $($Response.status) $($Response.body.error.message)"
                continue
            }
            foreach ($Result in $Response.body.value) {
                $Id = [string]$Result.itemId
                if (-not $ById.ContainsKey($Id)) { continue }
                [void]$Answered.Add($Id)
                $Entry = $ById[$Id]
                if ($Result.error -or -not $Result.data) {
                    $Warnings.Add("Export of item $Id failed: $($Result.error.message ?? $Result.error.code ?? 'no data returned')")
                    $Failed.Add($Entry.Item)
                    continue
                }
                try {
                    $Written = Write-CIPPCloudBackupItem -Context $Context -ItemKey "$($Entry.Key).fts" -Body ([Convert]::FromBase64String($Result.data)) -ContentType 'application/octet-stream'
                } catch {
                    $Warnings.Add("Storing item $Id failed: $($_.Exception.Message)")
                    $Failed.Add($Entry.Item)
                    continue
                }
                $Entry.ChangeKey = [string]$Result.changeKey
                $Entry.Fts = $Written
                $Bytes += [long]$Written.Bytes
                $Exported.Add($Entry)
            }
        }
        $Responses = $null
        foreach ($Request in $Batch) {
            foreach ($Id in $Request.body.itemIds) {
                if ($Answered.Contains($Id)) { continue }
                $Warnings.Add("Export of item $Id failed: $($RequestErrors[[string]$Request.id] ?? 'no result returned')")
                $Failed.Add($ById[$Id].Item)
            }
        }
    }

    # Export ids are not Graph message ids: match on creation second + change key. The match also supplies subject/sender.
    $Lookups = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Exported.Count; $i++) {
        $Entry = $Exported[$i]
        if ($Entry.Type -eq 'message' -and -not $Entry.WantsMime) { continue }
        $Created = $Entry.Item.Created
        $From = if ($Created -is [datetime]) { $Created.ToUniversalTime() } else { [System.DateTimeOffset]::Parse([string]$Created, [cultureinfo]::InvariantCulture).UtcDateTime }
        $From = $From.AddTicks(- ($From.Ticks % [timespan]::TicksPerSecond))
        $Filter = [uri]::EscapeDataString("createdDateTime ge $($From.ToString('yyyy-MM-ddTHH:mm:ssZ')) and createdDateTime lt $($From.AddSeconds(1).ToString('yyyy-MM-ddTHH:mm:ssZ'))")
        $Resource, $Select = switch ($Entry.Type) {
            'event' { 'events', 'id,changeKey,subject' }
            'contact' { 'contacts', 'id,changeKey,displayName' }
            default { 'messages', 'id,changeKey,subject,from,toRecipients,receivedDateTime,hasAttachments,internetMessageId' }
        }
        $Lookups.Add(@{ id = "$i"; method = 'GET'; url = "/users/$Owner/$Resource`?`$filter=$Filter&`$select=$Select" })
    }

    $Matched = [System.Collections.Generic.Dictionary[int, object]]::new()
    if ($Lookups.Count -gt 0) {
        $LookupResponses = try {
            New-GraphBulkRequest -tenantid $Tenant -asapp $true -Requests $Lookups.ToArray() -NoPaginateIds @($Lookups.id)
        } catch {
            $Warnings.Add("Looking up item details failed: $($_.Exception.Message)")
            @()
        }
        foreach ($Response in $LookupResponses) {
            if (([int]$Response.status) -ge 400) { continue }
            $Entry = $Exported[[int]$Response.id]
            $Candidates = @($Response.body.value)
            $Match = $null
            foreach ($Candidate in $Candidates) { if ([string]$Candidate.changeKey -ceq $Entry.ChangeKey) { $Match = $Candidate; break } }
            if (-not $Match -and $Candidates.Count -eq 1) { $Match = $Candidates[0] }
            if ($Match) { $Matched[[int]$Response.id] = $Match }
        }
    }

    $MimeUnits = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $Exported.Count; $i++) {
        $Entry = $Exported[$i]
        if (-not $Entry.WantsMime) { continue }
        if (-not $Matched.ContainsKey($i)) {
            $Warnings.Add("No matching message found to store item $($Entry.Item.Id) as .eml")
            $Failed.Add($Entry.Item)
            $Entry.MimeFailed = $true
            continue
        }
        $MimeUnits.Add(@{ Size = $Entry.Size; Request = @{ id = "$i"; method = 'GET'; url = "/users/$Owner/messages/$($Matched[$i].id)/`$value" } })
    }

    foreach ($Batch in (& $ToBatches $MimeUnits)) {
        $BatchError = $null
        $Responses = try {
            New-GraphBulkRequest -tenantid $Tenant -asapp $true -Requests $Batch
        } catch {
            $BatchError = $_.Exception.Message
            @()
        }
        $Answered = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($Response in $Responses) {
            $Entry = $Exported[[int]$Response.id]
            [void]$Answered.Add([string]$Response.id)
            if (([int]$Response.status) -ge 400 -or $Response.body -isnot [string]) {
                $Warnings.Add("Downloading message $($Entry.Item.Id) failed: HTTP $($Response.status) $($Response.body.error.message)")
                continue
            }
            try {
                # A non-JSON body in a $batch response is base64 encoded.
                $Written = Write-CIPPCloudBackupItem -Context $Context -ItemKey "$($Entry.Key).eml" -Body ([Convert]::FromBase64String($Response.body)) -ContentType 'message/rfc822'
                $Entry.Eml = $Written
                $Bytes += [long]$Written.Bytes
            } catch {
                $Warnings.Add("Storing message $($Entry.Item.Id) as .eml failed: $($_.Exception.Message)")
            }
        }
        $Responses = $null
        foreach ($Request in $Batch) {
            $Entry = $Exported[[int]$Request.id]
            if (-not $Entry.Eml) {
                if (-not $Answered.Contains($Request.id)) { $Warnings.Add("Downloading message $($Entry.Item.Id) failed: $($BatchError ?? 'no result returned')") }
                $Failed.Add($Entry.Item)
                $Entry.MimeFailed = $true
            }
        }
    }

    for ($i = 0; $i -lt $Exported.Count; $i++) {
        $Entry = $Exported[$i]
        $Detail = if ($Matched.ContainsKey($i)) { $Matched[$i] }
        $Extras = [ordered]@{ id = [string]$Entry.Item.Id }
        if ($Entry.Type -eq 'message') {
            $Extras.from = $Detail.from.emailAddress.address
            $Extras.to = @(foreach ($Recipient in $Detail.toRecipients) { $Recipient.emailAddress.address }) -join '; '
            $Extras.received = $Detail.receivedDateTime
            $Extras.internetMessageId = $Detail.internetMessageId
            $Extras.hasAttachments = $Detail.hasAttachments
            $Extras.eml = if ($Entry.Eml) { "$($Entry.Key).eml" } else { $null }
        }
        $IndexEntries.Add([pscustomobject]@{
                k = "$($Entry.Key).fts"
                p = $FolderPath
                n = if ($Entry.Type -eq 'contact') { $Detail.displayName } else { $Detail.subject }
                t = $Entry.Type
                s = $Entry.Size
                m = $Entry.Item.Modified
                v = $Entry.Fts.VersionId
                d = $false
                x = $Extras
            })
        if (-not $Entry.MimeFailed) { $Saved++ }
    }

    [pscustomobject]@{
        Items        = $Saved
        Bytes        = $Bytes
        Warnings     = $Warnings.ToArray()
        IndexEntries = $IndexEntries.ToArray()
        Failed       = $Failed.ToArray()
    }
}

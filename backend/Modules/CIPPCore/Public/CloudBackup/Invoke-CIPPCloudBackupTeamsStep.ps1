function Invoke-CIPPCloudBackupTeamsStep {
    <#
    .SYNOPSIS
        Backs up one page of a Teams owner's messages: a team's channel messages or a user's chats.
    .DESCRIPTION
        Each round pages through the Teams export API (getAllMessages) for a lastModifiedDateTime window, one page per
        step; the next round starts where the last window ended. Messages that fail are retried in a later run.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Context,
        $State
    )

    $Tenant = $Context.TenantFilter
    $OwnerId = $Context.OwnerId
    $Warnings = [System.Collections.Generic.List[string]]::new()
    $IndexEntries = [System.Collections.Generic.List[object]]::new()
    $Items = 0
    [long]$Bytes = 0
    $Deleted = 0
    $MaxRetry = 500
    $DateFormat = 'yyyy-MM-ddTHH:mm:ss.fffZ'

    $Kind = $State.Kind
    if (-not $Kind) {
        $Directory = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/directoryObjects/$($OwnerId)?`$select=id" -tenantid $Tenant -noPagination $true -SkipValueExtraction
        $Kind = if ($Directory.'@odata.type' -eq '#microsoft.graph.group') { 'Team' } else { 'UserChats' }
    }
    $IsChannel = $Kind -eq 'Team'

    $Channels = @{}
    if ($State.Channels -is [System.Collections.IDictionary]) {
        foreach ($Key in $State.Channels.Keys) { $Channels[$Key] = $State.Channels[$Key] }
    } elseif ($State.Channels) {
        foreach ($Property in $State.Channels.PSObject.Properties) { $Channels[$Property.Name] = $Property.Value }
    }
    $Retry = [System.Collections.Generic.List[object]]::new()
    foreach ($Entry in @($State.Retry)) {
        if ($Entry.u) { $Retry.Add(@{ u = [string]$Entry.u; a = [int]$Entry.a; r = [string]$Entry.r }) }
    }

    $NewState = @{
        Kind      = $Kind
        Since     = $State.Since
        Until     = $State.Until
        NextSince = $State.NextSince
        NextLink  = $State.NextLink
        Failures  = [int]$State.Failures
        TeamName  = $State.TeamName
        Channels  = $Channels
        Retry     = $Retry
    }
    # State can come back from JSON with the window dates already parsed into DateTime.
    foreach ($Name in 'Since', 'Until', 'NextSince') {
        if ($NewState[$Name] -is [datetime]) { $NewState[$Name] = $NewState[$Name].ToUniversalTime().ToString($DateFormat) }
    }
    $FirstRound = -not $NewState.Since
    $Done = $false
    $Attempts = @{}

    $Pending = [System.Collections.Generic.List[object]]::new()
    if (-not $NewState.NextLink) {
        foreach ($Entry in $Retry) {
            if ($Entry.r -ne $Context.RunId) { $Pending.Add($Entry) }
            if ($Pending.Count -ge 20) { break }
        }
    }

    if ($Pending.Count -gt 0) {
        $Requests = for ($i = 0; $i -lt $Pending.Count; $i++) {
            [void]$Retry.Remove($Pending[$i])
            $Attempts[$Pending[$i].u] = $Pending[$i].a
            @{ id = "$i"; method = 'GET'; url = $Pending[$i].u }
        }
        $Responses = New-GraphBulkRequest -tenantid $Tenant -asapp $true -Version 'v1.0' -Requests @($Requests)
        $Messages = foreach ($Response in $Responses) {
            $Entry = $Pending[[int]$Response.id]
            $Status = $Response.status -as [int]
            if ($Status -eq 200) {
                $Response.body
            } elseif ($Status -eq 404) {
                $Warnings.Add("Message $($Entry.u) no longer exists and was not backed up.")
            } elseif ($Entry.a + 1 -ge 3) {
                $Warnings.Add("Message $($Entry.u) was not backed up after 3 attempts: $($Response.body.error.message)")
            } else {
                $Retry.Add(@{ u = $Entry.u; a = $Entry.a + 1; r = [string]$Context.RunId })
            }
        }
    } else {
        $Continuation = [bool]$NewState.NextLink
        if ($Continuation) {
            $Url = $NewState.NextLink
        } else {
            # Leave a margin for messages the export store has not indexed yet.
            $UntilTime = [datetime]::UtcNow.AddMinutes(-5)
            $NewState.Until = $UntilTime.ToString($DateFormat)
            # The next window's 'gt' must still include a message modified exactly at this window's exclusive end.
            $NewState.NextSince = $UntilTime.AddMilliseconds(-1).ToString($DateFormat)
            $Since = $NewState.Since ?? '2000-01-01T00:00:00.000Z'
            $Path = if ($IsChannel) { "teams/$OwnerId/channels/getAllMessages" } else { "users/$OwnerId/chats/getAllMessages" }
            # https://learn.microsoft.com/en-us/microsoftteams/export-teams-content
            $Url = "https://graph.microsoft.com/v1.0/$($Path)?`$top=50&`$filter=lastModifiedDateTime gt $Since and lastModifiedDateTime lt $($NewState.Until)"

            if ($IsChannel) {
                $NameResponses = New-GraphBulkRequest -tenantid $Tenant -asapp $true -Version 'v1.0' -Requests @(
                    @{ id = 'team'; method = 'GET'; url = "/teams/$($OwnerId)?`$select=displayName" }
                    @{ id = 'channels'; method = 'GET'; url = "/teams/$OwnerId/channels?`$select=id,displayName" }
                )
                foreach ($Response in $NameResponses) {
                    if (($Response.status -as [int]) -ne 200) {
                        $Warnings.Add("Could not read the team's $($Response.id) names: $($Response.body.error.message)")
                    } elseif ($Response.id -eq 'team') {
                        $NewState.TeamName = $Response.body.displayName
                    } else {
                        $Channels.Clear()
                        foreach ($Channel in $Response.body.value) { $Channels[$Channel.id] = $Channel.displayName }
                    }
                }
            }
        }

        try {
            $Page = New-GraphGetRequest -uri $Url -tenantid $Tenant -AsApp $true -noPagination $true -SkipValueExtraction
        } catch {
            if (-not $Continuation) { throw }
            $NewState.Failures++
            $Warnings.Add("Reading the next page of messages failed: $($_.Exception.Message)")
            if ($NewState.Failures -ge 3) {
                $NewState.NextLink = $null
                $NewState.Failures = 0
                $Warnings.Add('The message page failed 3 times; the next run reads this time window again from the start.')
            }
            return [pscustomobject]@{ State = $NewState; Done = $true; Items = 0; Bytes = 0; Deleted = 0; Warnings = @($Warnings); IndexEntries = @() }
        }
        $NewState.Failures = 0
        $Messages = $Page.value
        $NewState.NextLink = $Page.'@odata.nextLink'
    }

    $ChatNames = @{}
    if (-not $IsChannel) {
        $ChatIds = [System.Collections.Generic.List[string]]::new()
        $Seen = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Message in @($Messages)) {
            if ($Message.chatId -and -not $Message.deletedDateTime -and $Seen.Add($Message.chatId)) { $ChatIds.Add($Message.chatId) }
        }
        if ($ChatIds.Count -gt 0) {
            $ChatRequests = for ($i = 0; $i -lt $ChatIds.Count; $i++) {
                @{ id = "$i"; method = 'GET'; url = "/chats/$($ChatIds[$i])?`$select=topic,chatType" }
            }
            foreach ($Response in (New-GraphBulkRequest -tenantid $Tenant -asapp $true -Version 'v1.0' -Requests @($ChatRequests))) {
                if (($Response.status -as [int]) -ne 200) { continue }
                $ChatNames[$ChatIds[[int]$Response.id]] = if ($Response.body.topic) { $Response.body.topic } else {
                    switch ($Response.body.chatType) {
                        'oneOnOne' { '1:1 chat' }
                        'group' { 'Group chat' }
                        'meeting' { 'Meeting chat' }
                        default { 'Chat' }
                    }
                }
            }
        }
    }

    $HostedPattern = 'https://graph\.microsoft\.[a-z.]+/(?:v1\.0|beta)(/[^"''\s<>]*?/hostedContents/([^"''\s<>]+?))/\$value'
    foreach ($Message in @($Messages)) {
        if ($null -eq $Message) { continue }
        $ConversationId = if ($IsChannel) { $Message.channelIdentity.channelId } else { $Message.chatId }
        # A user's getAllMessages also returns copies of channel messages the user saved; those have no chatId.
        if (-not $ConversationId) { continue }

        $MessageUrl = if (-not $IsChannel) {
            "/chats/$ConversationId/messages/$($Message.id)"
        } elseif ($Message.replyToId) {
            "/teams/$OwnerId/channels/$ConversationId/messages/$($Message.replyToId)/replies/$($Message.id)"
        } else {
            "/teams/$OwnerId/channels/$ConversationId/messages/$($Message.id)"
        }
        $ItemKey = "items/$ConversationId/$($Message.id).json"
        $Location = if ($IsChannel) { "$($NewState.TeamName)/$($Channels[$ConversationId] ?? $ConversationId)" } else { $ChatNames[$ConversationId] ?? $ConversationId }
        $SenderName = $Message.from.user.displayName ?? $Message.from.application.displayName ?? $Message.from.device.displayName ?? 'System'
        $Extras = @{
            from            = $SenderName
            fromId          = $Message.from.user.id ?? $Message.from.application.id
            createdDateTime = $Message.createdDateTime
            replyToId       = $Message.replyToId
            messageType     = $Message.messageType
        }
        if ($IsChannel) {
            $Extras.channelId = $ConversationId
            $Extras.teamId = $OwnerId
        } else {
            $Extras.chatId = $ConversationId
        }
        $Type = if ($IsChannel) { 'channelMessage' } else { 'chatMessage' }

        try {
            if ($Message.deletedDateTime) {
                if ($FirstRound) { continue }
                Remove-CIPPCloudBackupItem -Context $Context -ItemKey $ItemKey
                $Deleted++
                $IndexEntries.Add([pscustomobject]@{ k = $ItemKey; p = $Location; n = $SenderName; t = $Type; s = 0; m = $Message.lastModifiedDateTime; v = $null; d = $true; x = $Extras })
                continue
            }

            $HostedKeys = [System.Collections.Generic.List[string]]::new()
            $HostedIds = [System.Collections.Generic.List[string]]::new()
            $HostedSeen = [System.Collections.Generic.HashSet[string]]::new()
            $HostedRequests = foreach ($Match in [regex]::Matches([string]$Message.body.content, $HostedPattern)) {
                if (-not $HostedSeen.Add($Match.Groups[2].Value)) { continue }
                $HostedIds.Add($Match.Groups[2].Value)
                # ConsistencyLevel lets Graph return hosted content of edited messages.
                @{ id = "$($HostedIds.Count - 1)"; method = 'GET'; url = "$($Match.Groups[1].Value)/`$value"; headers = @{ ConsistencyLevel = 'eventual' } }
            }
            if ($HostedIds.Count -gt 0) {
                foreach ($Response in (New-GraphBulkRequest -tenantid $Tenant -asapp $true -Version 'v1.0' -Requests @($HostedRequests))) {
                    if (($Response.status -as [int]) -ne 200) { throw "Inline content returned HTTP $($Response.status)" }
                    $HostedKey = "items/$ConversationId/$($Message.id)/$($HostedIds[[int]$Response.id].Replace('/', '_'))"
                    # A $batch response carries binary bodies as base64.
                    $Written = Write-CIPPCloudBackupItem -Context $Context -ItemKey $HostedKey -Body ([Convert]::FromBase64String([string]$Response.body)) -ContentType ([string]$Response.headers.'Content-Type')
                    $Bytes += $Written.Bytes
                    $HostedKeys.Add($HostedKey)
                }
                $Extras.hostedContents = @($HostedKeys)
            }

            $Json = [CIPP.CippJson]::ToJson($Message, 30) ?? (ConvertTo-Json -InputObject $Message -Depth 30 -Compress)
            $Written = Write-CIPPCloudBackupItem -Context $Context -ItemKey $ItemKey -Body ([System.Text.Encoding]::UTF8.GetBytes($Json)) -ContentType 'application/json'
            $Items++
            $Bytes += $Written.Bytes

            $Text = ([System.Net.WebUtility]::HtmlDecode(([string]$Message.body.content -replace '<[^>]+>', ' ')) -replace '\s+', ' ').Trim()
            if ($Text.Length -gt 80) { $Text = $Text.Substring(0, 80) }
            $IndexEntries.Add([pscustomobject]@{
                    k = $ItemKey
                    p = $Location
                    n = if ($Text) { "$($SenderName): $Text" } else { $SenderName }
                    t = $Type
                    s = $Written.Size
                    m = $Message.lastModifiedDateTime
                    v = $Written.VersionId
                    d = $false
                    x = $Extras
                })
        } catch {
            $Existing = $null
            foreach ($Entry in $Retry) { if ($Entry.u -eq $MessageUrl) { $Existing = $Entry; break } }
            $Attempt = [Math]::Max([int]$Attempts[$MessageUrl], [int]$Existing.a) + 1
            if ($Existing) { [void]$Retry.Remove($Existing) }
            if ($Attempt -ge 3) {
                $Warnings.Add("Message $($Message.id) in $Location was not backed up after 3 attempts: $($_.Exception.Message)")
            } elseif ($Retry.Count -ge $MaxRetry) {
                throw "More than $MaxRetry messages are waiting to be retried; the last failure was: $($_.Exception.Message)"
            } else {
                $Retry.Add(@{ u = $MessageUrl; a = $Attempt; r = [string]$Context.RunId })
                $Warnings.Add("Message $($Message.id) in $Location will be retried in the next run: $($_.Exception.Message)")
            }
        }
    }

    if ($Pending.Count -eq 0 -and -not $NewState.NextLink) {
        $NewState.Since = $NewState.NextSince
        $NewState.Until = $null
        $NewState.NextSince = $null
        $Done = $true
    }

    [pscustomobject]@{
        State        = $NewState
        Done         = $Done
        Items        = $Items
        Bytes        = $Bytes
        Deleted      = $Deleted
        Warnings     = @($Warnings)
        IndexEntries = @($IndexEntries)
    }
}

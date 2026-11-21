function Invoke-CIPPCloudBackupExport {
    <#
    .SYNOPSIS
        Builds the .zip for a cloud backup export job and stores it at <policyId>/exports/<jobId>.zip.
    .DESCRIPTION
        Reads the job's selected items in batches and returns { Key; Bytes; Items; Failed; Warnings }. Mail is exported
        as .eml when one was stored, otherwise as a .json summary plus the stored .fts; files keep their paths; Teams
        conversations get the raw message JSON, inline images and one transcript.html each. Items that fail are listed
        in _export-report.txt inside the zip. The zip is built in a temporary file (deleted on return) and encrypted
        while it is uploaded when the policy has a key.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Workload = ([string]$Context.Workload).ToLowerInvariant()
    if ($Workload -notin @('exchange', 'onedrive', 'sharepoint', 'teams')) {
        throw [System.ArgumentException]::new("Unknown cloud backup workload '$($Context.Workload)'.")
    }
    $BatchSize = 200
    $MaxWarnings = 100
    $OwnerPrefix = ([string]$Context.OwnerPrefix).TrimEnd('/') + '/'
    $ExportKey = '{0}/exports/{1}.zip' -f $Context.PolicyId, $Context.JobId
    $Destination = $Context.Destination
    $KeyCache = @{}
    if ($Context.Key -and $Context.KeyId) { $KeyCache[([guid][string]$Context.KeyId).ToString()] = ([byte[]]$Context.Key).Clone() }

    $Warnings = [System.Collections.Generic.List[string]]::new()
    $Items = 0
    $Failed = 0
    $Problems = 0
    $InvalidName = [regex]::new('[\x00-\x1f"*:<>?\\|]')
    $Used = [System.Collections.Generic.HashSet[long]]::new()
    $Conversations = [System.Collections.Generic.Dictionary[string, hashtable]]::new([System.StringComparer]::Ordinal)
    $Utf8 = [System.Text.UTF8Encoding]::new($false)
    # Fastest grows incompressible files by about 5% on .NET 9 and later (zlib-ng); Optimal stores them as they are.
    $Level = [System.IO.Compression.CompressionLevel]::Optimal
    $TempFolder = [System.IO.Path]::GetTempPath()
    $Open = @{}

    try {
        foreach ($Name in 'Zip', 'Buffer', 'Plain', 'Fragments', 'Report') {
            $Open[$Name] = [System.IO.FileStream]::new([System.IO.Path]::Combine($TempFolder, "cipp-cb-export-$([guid]::NewGuid().ToString('N')).tmp"), [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None, 81920, [System.IO.FileOptions]::DeleteOnClose)
        }
        $ZipFile = $Open.Zip
        $Buffer = $Open.Buffer
        $Plain = $Open.Plain
        $Fragments = $Open.Fragments
        $ReportWriter = [System.IO.StreamWriter]::new($Open.Report, $Utf8, 65536, $true)
        $Archive = [System.IO.Compression.ZipArchive]::new($ZipFile, [System.IO.Compression.ZipArchiveMode]::Create, $true)

        $Offset = 0
        while ($true) {
            $Batch = @(Get-CIPPCloudBackupJobItemBatch -Context $Context -Offset $Offset -Count $BatchSize)
            foreach ($Entry in $Batch) {
                if ($null -eq $Entry -or $Entry.Deleted) { continue }
                $Type = [string]$Entry.Type
                $IsFolder = $Type -eq 'folder'
                if ($IsFolder -and $Workload -eq 'teams') { continue }
                $Extra = $Entry.Extra
                $ItemKey = ([string]$Entry.Key).TrimStart('/')

                $RawPath = switch ($Workload) {
                    'exchange' { '{0}/{1}' -f $Entry.Path, $(if ($Entry.Name) { $Entry.Name } elseif ($IsFolder) { 'Folder' } else { '(no subject)' }) }
                    'sharepoint' { '{0}{1}/{2}' -f $Extra.driveName, ([string]$Entry.Path).TrimEnd('/'), $Entry.Name }
                    'onedrive' { '{0}/{1}' -f ([string]$Entry.Path).TrimEnd('/'), $Entry.Name }
                    'teams' { if ($Entry.Path) { [string]$Entry.Path } else { $ItemKey.Split('/')[1] } }
                }
                $Segments = [System.Collections.Generic.List[string]]::new()
                foreach ($Segment in ([string]$RawPath).Split('/')) {
                    if (-not $Segment) { continue }
                    $Clean = $InvalidName.Replace($Segment, '_').Trim().TrimEnd('.')
                    if ($Clean.Length -gt 120) { $Clean = $Clean.Substring(0, 120).TrimEnd() }
                    $Segments.Add($(if ($Clean) { $Clean } else { '_' }))
                }
                if ($Segments.Count -eq 0) { $Segments.Add('_') }
                $SafePath = $Segments -join '/'

                if ($IsFolder) {
                    if ($Used.Add([System.BitConverter]::ToInt64([System.Security.Cryptography.SHA256]::HashData($Utf8.GetBytes("$SafePath/".ToLowerInvariant())), 0))) {
                        $null = $Archive.CreateEntry("$SafePath/")
                    }
                    continue
                }

                try {
                    $Outputs = [System.Collections.Generic.List[hashtable]]::new()

                    if ($Workload -eq 'exchange') {
                        $Hash8 = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Utf8.GetBytes($ItemKey)), 0, 4)
                        $Base = "$SafePath [$Hash8]"
                        $ItemBase = if ($ItemKey.EndsWith('.fts')) { $ItemKey.Substring(0, $ItemKey.Length - 4) } else { $ItemKey }
                        $EmlKey = if ($Extra.eml) { [string]$Extra.eml } else { $null }
                        $EmlVersion = $null
                        if ($EmlKey -and $Entry.VersionId) {
                            $FtsFull = "$OwnerPrefix$ItemKey"
                            $EmlFull = "$OwnerPrefix$EmlKey"
                            $Versions = @(Get-CIPPCloudBackupObjectVersionList -Destination $Destination -Prefix "$OwnerPrefix$ItemBase.")
                            $FtsTime = $null
                            foreach ($Version in $Versions) {
                                if ($Version.Key -eq $FtsFull -and [string]$Version.VersionId -eq [string]$Entry.VersionId) { $FtsTime = [datetime]$Version.LastModified; break }
                            }
                            if ($null -ne $FtsTime) {
                                $NextFts = [datetime]::MaxValue
                                foreach ($Version in $Versions) {
                                    if ($Version.Key -eq $FtsFull -and [datetime]$Version.LastModified -gt $FtsTime -and [datetime]$Version.LastModified -lt $NextFts) { $NextFts = [datetime]$Version.LastModified }
                                }
                                $Best = $null
                                foreach ($Version in $Versions) {
                                    if ($Version.Key -ne $EmlFull -or $Version.IsDeleteMarker) { continue }
                                    $At = [datetime]$Version.LastModified
                                    if ($At -ge $FtsTime -and $At -lt $NextFts -and ($null -eq $Best -or $At -lt [datetime]$Best.LastModified)) { $Best = $Version }
                                }
                                if ($Best) { $EmlVersion = [string]$Best.VersionId } else { $EmlKey = $null }
                            }
                        }

                        $Got = $null
                        if ($EmlKey) {
                            $Plain.SetLength(0)
                            $Got = Get-CIPPCloudBackupExportStream -Destination $Destination -Key "$OwnerPrefix$EmlKey" -VersionId $EmlVersion -OutStream $Plain -KeyCache $KeyCache -BufferStream $Buffer
                            if ($Got) { $Outputs.Add(@{ Base = $Base; Ext = '.eml'; Plain = $true }) }
                        }
                        if (-not $Got) {
                            $Plain.SetLength(0)
                            $Got = Get-CIPPCloudBackupExportStream -Destination $Destination -Key "$OwnerPrefix$ItemKey" -VersionId $Entry.VersionId -OutStream $Plain -KeyCache $KeyCache -BufferStream $Buffer
                            if (-not $Got) { throw 'The stored item was not found.' }
                            $Details = [ordered]@{
                                type              = $Type
                                name              = $Entry.Name
                                folder            = $Entry.Path
                                modified          = $Entry.Modified
                                size              = $Entry.Size
                                from              = $Extra.from
                                to                = $Extra.to
                                received          = $Extra.received
                                internetMessageId = $Extra.internetMessageId
                                hasAttachments    = $Extra.hasAttachments
                                itemId            = $Extra.id
                                content           = "$([System.IO.Path]::GetFileName($Base)).fts"
                            }
                            $Json = [CIPP.CippJson]::ToJson($Details, 5) ?? (ConvertTo-Json -InputObject $Details -Depth 5)
                            $Outputs.Add(@{ Base = $Base; Ext = '.json'; Bytes = $Utf8.GetBytes($Json) })
                            $Outputs.Add(@{ Base = $Base; Ext = '.fts'; Plain = $true })
                        }
                    } elseif ($Workload -ne 'teams') {
                        $Plain.SetLength(0)
                        $Got = Get-CIPPCloudBackupExportStream -Destination $Destination -Key "$OwnerPrefix$ItemKey" -VersionId $Entry.VersionId -OutStream $Plain -KeyCache $KeyCache -BufferStream $Buffer
                        if (-not $Got) { throw 'The stored file was not found.' }
                        $Slash = $SafePath.LastIndexOf('/')
                        $Dot = $SafePath.LastIndexOf('.')
                        if ($Dot -gt $Slash + 1) {
                            $Outputs.Add(@{ Base = $SafePath.Substring(0, $Dot); Ext = $SafePath.Substring($Dot); Plain = $true })
                        } else {
                            $Outputs.Add(@{ Base = $SafePath; Ext = ''; Plain = $true })
                        }
                    }

                    if ($Workload -ne 'teams') {
                        foreach ($Output in $Outputs) {
                            $Candidate = "$($Output.Base)$($Output.Ext)"
                            $Copy = 1
                            while (-not $Used.Add([System.BitConverter]::ToInt64([System.Security.Cryptography.SHA256]::HashData($Utf8.GetBytes($Candidate.ToLowerInvariant())), 0))) {
                                $Copy++
                                $Candidate = "$($Output.Base) ($Copy)$($Output.Ext)"
                            }
                            $ZipStream = $Archive.CreateEntry($Candidate, $Level).Open()
                            try {
                                if ($Output.Plain) {
                                    $Plain.Position = 0
                                    $Plain.CopyTo($ZipStream, 1MB)
                                } else {
                                    $ZipStream.Write($Output.Bytes, 0, $Output.Bytes.Length)
                                }
                            } finally {
                                $ZipStream.Dispose()
                            }
                        }
                        $Items++
                        continue
                    }

                    $KeyParts = $ItemKey.Split('/')
                    $ConversationId = if ($Extra.chatId) { [string]$Extra.chatId } elseif ($Extra.channelId) { [string]$Extra.channelId } else { $KeyParts[1] }
                    $MessageId = [System.IO.Path]::GetFileNameWithoutExtension($KeyParts[-1])
                    $SafeMessageId = $MessageId -replace '[^A-Za-z0-9_-]', '_'

                    $Plain.SetLength(0)
                    $Got = Get-CIPPCloudBackupExportStream -Destination $Destination -Key "$OwnerPrefix$ItemKey" -VersionId $Entry.VersionId -OutStream $Plain -KeyCache $KeyCache -BufferStream $Buffer
                    if (-not $Got) { throw 'The stored message was not found.' }
                    $Plain.Position = 0
                    $Reader = [System.IO.StreamReader]::new($Plain, $Utf8, $false, 65536, $true)
                    try { $Json = $Reader.ReadToEnd() } finally { $Reader.Dispose() }
                    $Message = [CIPP.CippJson]::ConvertFromJson($Json)
                    if ($null -eq $Message) { throw 'The stored message is not valid JSON.' }

                    $Conversation = $null
                    if (-not $Conversations.TryGetValue($ConversationId, [ref]$Conversation)) {
                        $Folder = $SafePath
                        $Copy = 1
                        while (-not $Used.Add([System.BitConverter]::ToInt64([System.Security.Cryptography.SHA256]::HashData($Utf8.GetBytes("$Folder/".ToLowerInvariant())), 0))) {
                            $Copy++
                            $Folder = "$SafePath ($Copy)"
                        }
                        $Conversation = @{
                            Folder  = $Folder
                            Title   = $RawPath
                            Ids     = [System.Collections.Generic.List[string]]::new()
                            ReplyTo = [System.Collections.Generic.List[string]]::new()
                            Created = [System.Collections.Generic.List[long]]::new()
                            Offset  = [System.Collections.Generic.List[long]]::new()
                            Length  = [System.Collections.Generic.List[int]]::new()
                        }
                        $Conversations[$ConversationId] = $Conversation
                    }
                    $Folder = $Conversation.Folder

                    $ZipStream = $Archive.CreateEntry("$Folder/messages/$SafeMessageId.json", $Level).Open()
                    try {
                        $Plain.Position = 0
                        $Plain.CopyTo($ZipStream, 1MB)
                    } finally {
                        $ZipStream.Dispose()
                    }

                    $Images = [System.Collections.Generic.List[string]]::new()
                    $HostedIndex = 0
                    foreach ($HostedKey in @($Extra.hostedContents)) {
                        if (-not $HostedKey) { continue }
                        $HostedIndex++
                        try {
                            $Plain.SetLength(0)
                            $HostedGot = Get-CIPPCloudBackupExportStream -Destination $Destination -Key "$OwnerPrefix$(([string]$HostedKey).TrimStart('/'))" -OutStream $Plain -KeyCache $KeyCache -BufferStream $Buffer
                            if (-not $HostedGot) { throw 'it was not found in the backup' }
                        } catch {
                            $Problems++
                            $Line = "$($RawPath): an inline image of message $MessageId could not be exported: $($_.Exception.Message)"
                            $ReportWriter.WriteLine($Line)
                            if ($Warnings.Count -lt $MaxWarnings) { $Warnings.Add($Line) }
                            continue
                        }
                        $Extension = switch -Wildcard ([string]$HostedGot.ContentType) {
                            'image/png*' { '.png' }
                            'image/jpeg*' { '.jpg' }
                            'image/gif*' { '.gif' }
                            'image/webp*' { '.webp' }
                            'image/bmp*' { '.bmp' }
                            default { '' }
                        }
                        $HostedName = "$SafeMessageId-$HostedIndex$Extension"
                        $ZipStream = $Archive.CreateEntry("$Folder/hosted/$HostedName", $Level).Open()
                        try {
                            $Plain.Position = 0
                            $Plain.CopyTo($ZipStream, 1MB)
                        } finally {
                            $ZipStream.Dispose()
                        }
                        $Images.Add("hosted/$HostedName")
                    }

                    $Created = $Message.createdDateTime ?? $Extra.createdDateTime
                    $CreatedUtc = [datetime]::MinValue
                    if ($Created -is [datetime]) {
                        $CreatedUtc = $Created.ToUniversalTime()
                    } else {
                        $Parsed = [System.DateTimeOffset]::MinValue
                        if ([System.DateTimeOffset]::TryParse([string]$Created, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Parsed)) { $CreatedUtc = $Parsed.UtcDateTime }
                    }
                    $SenderName = $Message.from.user.displayName ?? $Message.from.application.displayName ?? $Message.from.device.displayName ?? $Extra.from ?? 'System'
                    $Content = [string]$Message.body.content
                    if ([string]$Message.body.contentType -eq 'html') {
                        $Text = [regex]::Replace($Content, '<\s*br\s*/?\s*>|</\s*(p|div|li|tr|h[1-6])\s*>', "`n", 'IgnoreCase')
                        $Text = [regex]::Replace($Text, '<img\b[^>]*>', '[image]', 'IgnoreCase')
                        $Text = [System.Net.WebUtility]::HtmlDecode([regex]::Replace($Text, '<[^>]*>', ''))
                    } else {
                        $Text = $Content
                    }
                    $Text = [regex]::Replace($Text, '\n{3,}', "`n`n").Trim()
                    if (-not $Text -and [string]$Message.messageType -and [string]$Message.messageType -ne 'message') { $Text = "[$($Message.messageType)]" }
                    $ReplyToId = [string]$Message.replyToId

                    $Html = [System.Text.StringBuilder]::new()
                    $null = $Html.Append('<div class="msg').Append($(if ($ReplyToId) { ' reply' } else { '' })).Append('"><div class="meta"><span class="from">')
                    $null = $Html.Append([System.Net.WebUtility]::HtmlEncode([string]$SenderName)).Append('</span> <span class="time">')
                    $null = $Html.Append($(if ($CreatedUtc -ne [datetime]::MinValue) { $CreatedUtc.ToString('yyyy-MM-dd HH:mm', [cultureinfo]::InvariantCulture) + ' UTC' } else { '' })).Append('</span>')
                    if ($Message.lastEditedDateTime) { $null = $Html.Append(' <span class="edited">(edited)</span>') }
                    $null = $Html.Append('</div>')
                    if ($Message.subject) { $null = $Html.Append('<div class="subject">').Append([System.Net.WebUtility]::HtmlEncode([string]$Message.subject)).Append('</div>') }
                    $null = $Html.Append('<div class="body">').Append([System.Net.WebUtility]::HtmlEncode($Text)).Append('</div>')
                    foreach ($Image in $Images) {
                        $null = $Html.Append('<img src="').Append([System.Net.WebUtility]::HtmlEncode($Image)).Append('" alt="Image">')
                    }
                    $AttachmentHtml = foreach ($Attachment in @($Message.attachments)) {
                        if ($null -eq $Attachment) { continue }
                        $Label = [System.Net.WebUtility]::HtmlEncode([string]($Attachment.name ?? $Attachment.contentType ?? 'Attachment'))
                        $Url = [string]$Attachment.contentUrl
                        if ($Url.StartsWith('https://', [System.StringComparison]::OrdinalIgnoreCase)) {
                            '<li><a href="{0}" rel="noopener noreferrer">{1}</a></li>' -f [System.Net.WebUtility]::HtmlEncode($Url), $Label
                        } else {
                            "<li>$Label</li>"
                        }
                    }
                    if ($AttachmentHtml) { $null = $Html.Append('<ul class="attachments">').Append(-join $AttachmentHtml).Append('</ul>') }
                    $null = $Html.Append("</div>`n")

                    $FragmentBytes = $Utf8.GetBytes($Html.ToString())
                    $Conversation.Ids.Add($MessageId)
                    $Conversation.ReplyTo.Add($ReplyToId)
                    $Conversation.Created.Add($CreatedUtc.Ticks)
                    $Conversation.Offset.Add($Fragments.Position)
                    $Conversation.Length.Add($FragmentBytes.Length)
                    $Fragments.Write($FragmentBytes, 0, $FragmentBytes.Length)
                    $Items++
                } catch {
                    $Failed++
                    $Line = "$($RawPath): could not be exported: $($_.Exception.Message)"
                    $ReportWriter.WriteLine($Line)
                    if ($Warnings.Count -lt $MaxWarnings) { $Warnings.Add($Line) }
                }
            }
            if ($Batch.Count -lt $BatchSize) { break }
            $Offset += $Batch.Count
        }

        $Head = "<!DOCTYPE html>`n<html lang=`"en`"><head><meta charset=`"utf-8`"><meta http-equiv=`"Content-Security-Policy`" content=`"default-src 'none'; img-src 'self' file: data:; style-src 'unsafe-inline'`"><meta name=`"viewport`" content=`"width=device-width, initial-scale=1`"><title>{0}</title><style>body{{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#222;background:#fff}}.note{{color:#666}}.msg{{border-bottom:1px solid #eee;padding:8px 0}}.reply{{margin-left:32px}}.meta{{font-size:13px;color:#555}}.from{{font-weight:600;color:#222}}.subject{{font-weight:600;margin-top:4px}}.body{{white-space:pre-wrap;margin-top:4px}}img{{max-width:480px;display:block;margin-top:6px}}</style></head><body><h1>{0}</h1><p class=`"note`">{1} messages exported by CIPP from the backup taken at {2}.</p>`n"
        $FragmentBuffer = [byte[]]::new(65536)
        foreach ($Conversation in $Conversations.Values) {
            $Count = $Conversation.Ids.Count
            $TicksById = [System.Collections.Generic.Dictionary[string, long]]::new([System.StringComparer]::Ordinal)
            for ($i = 0; $i -lt $Count; $i++) { $TicksById[$Conversation.Ids[$i]] = $Conversation.Created[$i] }
            $SortKeys = [string[]]::new($Count)
            $Order = [int[]]::new($Count)
            for ($i = 0; $i -lt $Count; $i++) {
                $Root = $Conversation.Ids[$i]
                $RootTicks = $Conversation.Created[$i]
                $Depth = 0
                $Parent = $Conversation.ReplyTo[$i]
                $ParentTicks = 0L
                if ($Parent -and $TicksById.TryGetValue($Parent, [ref]$ParentTicks)) {
                    $Root = $Parent
                    $RootTicks = $ParentTicks
                    $Depth = 1
                }
                $SortKeys[$i] = '{0:D19}|{1}|{2}|{3:D19}|{4}' -f $RootTicks, $Root, $Depth, $Conversation.Created[$i], $Conversation.Ids[$i]
                $Order[$i] = $i
            }
            [System.Array]::Sort($SortKeys, $Order, [System.StringComparer]::Ordinal)

            $ZipStream = $Archive.CreateEntry("$($Conversation.Folder)/transcript.html", $Level).Open()
            try {
                $HeadBytes = $Utf8.GetBytes(($Head -f [System.Net.WebUtility]::HtmlEncode([string]$Conversation.Title), $Count, [System.Net.WebUtility]::HtmlEncode([string]$Context.RunStamp)))
                $ZipStream.Write($HeadBytes, 0, $HeadBytes.Length)
                foreach ($i in $Order) {
                    $Length = $Conversation.Length[$i]
                    if ($FragmentBuffer.Length -lt $Length) { $FragmentBuffer = [byte[]]::new($Length) }
                    $Fragments.Position = $Conversation.Offset[$i]
                    $Filled = 0
                    while ($Filled -lt $Length) {
                        $Read = $Fragments.Read($FragmentBuffer, $Filled, $Length - $Filled)
                        if ($Read -le 0) { throw 'The transcript working file ended early.' }
                        $Filled += $Read
                    }
                    $ZipStream.Write($FragmentBuffer, 0, $Length)
                }
                $TailBytes = $Utf8.GetBytes("</body></html>`n")
                $ZipStream.Write($TailBytes, 0, $TailBytes.Length)
            } finally {
                $ZipStream.Dispose()
            }
        }

        $ReportWriter.Flush()
        $ZipStream = $Archive.CreateEntry('_export-report.txt', $Level).Open()
        try {
            $Summary = @(
                'CIPP Cloud Backup export'
                "Tenant: $($Context.TenantFilter)"
                "Service: $Workload"
                "Owner: $(if ($Context.SourceOwnerName) { "$($Context.SourceOwnerName) ($($Context.SourceOwnerId))" } else { $Context.SourceOwnerId })"
                "Backup point in time: $($Context.RunStamp)"
                "Items exported: $Items"
                "Items that could not be exported: $Failed"
                ''
                $(if ($Failed -or $Problems) { 'Problems:' } else { 'No problems.' })
                ''
            ) -join "`r`n"
            $SummaryBytes = $Utf8.GetBytes($Summary)
            $ZipStream.Write($SummaryBytes, 0, $SummaryBytes.Length)
            $Open.Report.Position = 0
            $Open.Report.CopyTo($ZipStream, 1MB)
        } finally {
            $ZipStream.Dispose()
        }

        $Archive.Dispose()
        $Archive = $null
        $ZipFile.Position = 0
        $SendParams = @{ Destination = $Destination; Key = $ExportKey; Stream = $ZipFile; ContentType = 'application/zip' }
        if ($Context.Key) {
            $SendParams.KeyId = [string]$Context.KeyId
            $SendParams.EncryptionKey = [byte[]]$Context.Key
        }
        $Sent = Send-CIPPCloudBackupObjectStream @SendParams

        [pscustomobject]@{
            Key      = $ExportKey
            Bytes    = [long]$Sent.Bytes
            Items    = $Items
            Failed   = $Failed
            Warnings = $Warnings.ToArray()
        }
    } finally {
        if ($Archive) { try { $Archive.Dispose() } catch { Write-Verbose "Closing the export archive failed: $($_.Exception.Message)" } }
        if ($ReportWriter) { $ReportWriter.Dispose() }
        foreach ($Stream in $Open.Values) { $Stream.Dispose() }
        foreach ($Cached in $KeyCache.Values) { [System.Array]::Clear($Cached, 0, $Cached.Length) }
    }
}

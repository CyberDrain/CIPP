BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $noPagination, [switch]$SkipValueExtraction, [switch]$ComplexFilter, [switch]$Stream, $extraHeaders) }
    function New-GraphBulkRequest { param($tenantid, $asapp, $Requests, $NoPaginateIds) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams, $Select, [switch]$StreamPages) }
    function Write-CIPPCloudBackupItem { param($Context, $ItemKey, $Body, $Stream, $ContentType, $Metadata) }
    function Remove-CIPPCloudBackupItem { param($Context, $ItemKey) }
    function Get-CIPPCloudBackupObjectList { param($Destination, $Prefix) }
    foreach ($Name in 'Get-CIPPCloudBackupExchangeOwner', 'Invoke-CIPPCloudBackupExchangeStep', 'Save-CIPPCloudBackupExchangeItem') {
        . (Join-Path $BackendRoot "Modules/CIPPCore/Public/CloudBackup/$Name.ps1")
    }

    $script:Graph = 'https://graph.microsoft.com/beta'
    $script:Mbx = 'MBX:e0643f21@a7809c93'
    $script:InboxId = 'AA/B+C='
    $script:InboxKey = 'AA-B_C='
    $script:Context = [pscustomobject]@{
        TenantFilter = 'contoso.onmicrosoft.com'
        OwnerId      = 'user-1'
        OwnerPrefix  = 'policy/customer/exchange/user-1/'
        Destination  = [pscustomobject]@{ Provider = 'AzureBlob' }
    }

    function script:ConvertTo-B64 { param([string]$Text) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text)) }

    function script:New-MailboxItem {
        param([string]$Id, [string]$Class = 'IPM.Note', [int]$Second = 0, [long]$Size = 100)
        $Created = '2024-05-01T10:00:{0:00}Z' -f $Second
        @{ id = $Id; type = $Class; size = $Size; createdDateTime = $Created; lastModifiedDateTime = $Created; changeKey = "CK-$Id" }
        $script:GraphObjects[$Created] = @(@{ id = "G-$Id"; changeKey = "CK-$Id"; subject = "Subject $Id"; displayName = "Name $Id"; from = @{ emailAddress = @{ address = 'from@contoso.com' } }; toRecipients = @(@{ emailAddress = @{ address = 'a@contoso.com' } }, @{ emailAddress = @{ address = 'b@contoso.com' } }); receivedDateTime = $Created; hasAttachments = $true; internetMessageId = "<$Id@contoso.com>" })
    }

    function script:Invoke-Run {
        param($State, [int]$MaxSteps = 50)
        $Steps = 0
        $All = [System.Collections.Generic.List[object]]::new()
        do {
            $Result = Invoke-CIPPCloudBackupExchangeStep -Context $script:Context -State $State
            $State = $Result.State | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
            $All.Add($Result)
            $Steps++
        } until ($Result.Done -or $Steps -ge $MaxSteps)
        [pscustomobject]@{ State = $State; Steps = $All; Done = $Result.Done }
    }
}

Describe 'Get-CIPPCloudBackupExchangeOwner' {
    It 'returns licensed user mailboxes and shared mailboxes only' {
        Mock New-GraphGetRequest { @{ id = 'licensed' } }
        Mock New-ExoRequest {
            @{ Value = @(
                    @{ ExternalDirectoryObjectId = 'licensed'; UserPrincipalName = 'a@contoso.com'; DisplayName = 'A'; RecipientTypeDetails = 'UserMailbox' }
                    @{ ExternalDirectoryObjectId = 'unlicensed'; UserPrincipalName = 'b@contoso.com'; DisplayName = 'B'; RecipientTypeDetails = 'UserMailbox' }
                    @{ ExternalDirectoryObjectId = 'shared'; UserPrincipalName = 'shared@contoso.com'; DisplayName = 'Shared'; RecipientTypeDetails = 'SharedMailbox' }
                    @{ ExternalDirectoryObjectId = $null; UserPrincipalName = 'x@contoso.com'; DisplayName = 'No directory object'; RecipientTypeDetails = 'SharedMailbox' }
                ) }
        }
        $Owners = @(Get-CIPPCloudBackupExchangeOwner -TenantFilter 'contoso.onmicrosoft.com')
        $Owners.OwnerId | Should -Be @('licensed', 'shared')
        $Owners.OwnerType | Should -Be @('UserMailbox', 'SharedMailbox')
        $Owners[1].UserPrincipalName | Should -Be 'shared@contoso.com'
        $Owners[0].SiteUrl | Should -BeNullOrEmpty
        Should -Invoke New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Get-Mailbox' -and $cmdParams.RecipientTypeDetails -contains 'SharedMailbox' -and $cmdParams.RecipientTypeDetails -notcontains 'RoomMailbox' }
    }
}

Describe 'Invoke-CIPPCloudBackupExchangeStep' {
    BeforeEach {
        $script:GraphObjects = @{}
        $script:Pages = [ordered]@{}
        $script:Writes = [ordered]@{}
        $script:Removes = [System.Collections.Generic.List[string]]::new()
        $script:ExportRequests = [System.Collections.Generic.List[object]]::new()
        $script:Batches = [System.Collections.Generic.List[object]]::new()
        $script:ExportErrors = @{}
        $script:GetUris = [System.Collections.Generic.List[string]]::new()
        $script:FailGet = $false

        Mock New-GraphGetRequest {
            $script:GetUris.Add($uri)
            if ($script:FailGet) { throw 'Service unavailable' }
            if ($uri -like '*/settings/exchange') { return @{ primaryMailboxId = $script:Mbx } }
            foreach ($Key in $script:Pages.Keys) { if ($uri.Contains($Key)) { return $script:Pages[$Key] } }
            throw "Unexpected GET $uri"
        }
        Mock New-GraphBulkRequest {
            $script:Batches.Add(@($Requests))
            foreach ($Request in $Requests) {
                if ($Request.method -eq 'POST') {
                    $script:ExportRequests.Add(@($Request.body.itemIds))
                    $Value = foreach ($Id in $Request.body.itemIds) {
                        if ($script:ExportErrors.ContainsKey($Id)) { @{ itemId = $Id; error = @{ message = $script:ExportErrors[$Id] } } }
                        else { @{ itemId = $Id; changeKey = "CK-$Id"; data = (ConvertTo-B64 "FTS:$Id") } }
                    }
                    @{ id = $Request.id; status = 200; body = @{ value = @($Value) } }
                } elseif ($Request.url -like '*/$value') {
                    $GraphId = ($Request.url -split '/')[-2]
                    @{ id = $Request.id; status = 200; body = (ConvertTo-B64 "MIME:$GraphId") }
                } else {
                    $Url = [uri]::UnescapeDataString($Request.url)
                    $null = $Url -match 'createdDateTime ge (\S+) and'
                    $Found = $script:GraphObjects[$Matches[1]]
                    @{ id = $Request.id; status = 200; body = @{ value = $(if ($Found) { @($Found) } else { @() }) } }
                }
            }
        }
        Mock Write-CIPPCloudBackupItem {
            $script:Writes[$ItemKey] = [Text.Encoding]::UTF8.GetString($Body)
            [pscustomobject]@{ Key = $ItemKey; Bytes = $Body.Length; VersionId = "v-$ItemKey" }
        }
        Mock Remove-CIPPCloudBackupItem { $script:Removes.Add($ItemKey) }
        Mock Get-CIPPCloudBackupObjectList { @() }

        $script:Pages["/admin/exchange/mailboxes/$Mbx/folders/delta?`$select"] = @{
            value             = @(
                @{ id = $InboxId; displayName = 'Inbox'; parentFolderId = 'ROOT'; type = 'IPF.Note'; isHidden = $false }
                @{ id = 'SUB'; displayName = 'Projects'; parentFolderId = $InboxId; type = 'IPF.Note'; isHidden = $false }
                @{ id = 'ROOT'; displayName = 'Top of Information Store'; parentFolderId = 'X'; type = $null; isHidden = $false }
            )
            '@odata.nextLink' = "$Graph/admin/exchange/mailboxes/$Mbx/folders/delta?`$skiptoken=F2"
        }
        $script:Pages['folders/delta?$skiptoken=F2'] = @{
            value              = @(
                @{ id = 'CAL'; displayName = 'Calendar'; parentFolderId = 'ROOT'; type = 'IPF.Appointment'; isHidden = $false }
                @{ id = 'CON'; displayName = 'Contacts'; parentFolderId = 'ROOT'; type = 'IPF.Contact'; isHidden = $false }
                @{ id = 'HID'; displayName = 'Hidden'; parentFolderId = 'ROOT'; type = 'IPF.Note'; isHidden = $true }
                @{ id = 'TSK'; displayName = 'Tasks'; parentFolderId = 'ROOT'; type = 'IPF.Task'; isHidden = $false }
            )
            '@odata.deltaLink' = "$Graph/admin/exchange/mailboxes/$Mbx/folders/delta?`$deltatoken=F3"
        }
        $script:Pages["folders/$([uri]::EscapeDataString($InboxId))/items/delta?`$select"] = @{
            value             = @((New-MailboxItem -Id 'm1' -Second 1), (New-MailboxItem -Id 'm2' -Second 2 -Class 'IPM.Schedule.Meeting.Request'))
            '@odata.nextLink' = "$Graph/admin/exchange/mailboxes/$Mbx/folders/inbox/items/delta?`$skiptoken=I2"
        }
        $script:Pages['items/delta?$skiptoken=I2'] = @{
            value              = @((New-MailboxItem -Id 'm3' -Second 3 -Class 'REPORT.IPM.Note.NDR'))
            '@odata.deltaLink' = "$Graph/admin/exchange/mailboxes/$Mbx/folders/inbox/items/delta?`$deltatoken=I3"
        }
        $script:Pages['folders/SUB/items/delta?$select'] = @{ value = @(); '@odata.deltaLink' = "$Graph/x/folders/SUB/items/delta?`$deltatoken=S1" }
        $script:Pages['folders/CAL/items/delta?$select'] = @{ value = @((New-MailboxItem -Id 'e1' -Second 4 -Class 'IPM.Appointment')); '@odata.deltaLink' = "$Graph/x/folders/CAL/items/delta?`$deltatoken=C1" }
        $script:Pages['folders/CON/items/delta?$select'] = @{ value = @((New-MailboxItem -Id 'c1' -Second 5 -Class 'IPM.Contact')); '@odata.deltaLink' = "$Graph/x/folders/CON/items/delta?`$deltatoken=N1" }
    }

    It 'backs up the whole mailbox in bounded steps on the first run' {
        $Run = Invoke-Run -State $null
        $Run.Done | Should -BeTrue
        $Run.Steps.Count | Should -Be 8

        $Writes.Keys | Should -Be @(
            "items/$InboxKey/m1.fts", "items/$InboxKey/m2.fts", "items/$InboxKey/m1.eml", "items/$InboxKey/m2.eml",
            "items/$InboxKey/m3.fts", 'items/CAL/e1.fts', 'items/CON/c1.fts')
        $Writes["items/$InboxKey/m1.fts"] | Should -Be 'FTS:m1'
        $Writes["items/$InboxKey/m2.eml"] | Should -Be 'MIME:G-m2'

        $GetUris.Where({ $_ -match '/folders/(HID|TSK|ROOT)/' }).Count | Should -Be 0

        $Entries = @($Run.Steps.IndexEntries)
        $Folder = $Entries.Where({ $_.t -eq 'folder' -and $_.n -eq 'Projects' })[0]
        $Folder.k | Should -Be 'items/SUB/'
        $Folder.p | Should -Be 'Top of Information Store/Inbox'
        $M1 = $Entries.Where({ $_.k -eq "items/$InboxKey/m1.fts" })[0]
        $M1.p | Should -Be 'Top of Information Store/Inbox'
        $M1.n | Should -Be 'Subject m1'
        $M1.t | Should -Be 'message'
        $M1.s | Should -Be 100
        $M1.v | Should -Be "v-items/$InboxKey/m1.fts"
        $M1.d | Should -BeFalse
        $M1.x.from | Should -Be 'from@contoso.com'
        $M1.x.to | Should -Be 'a@contoso.com; b@contoso.com'
        $M1.x.internetMessageId | Should -Be '<m1@contoso.com>'
        $M1.x.hasAttachments | Should -BeTrue
        $M1.x.eml | Should -Be "items/$InboxKey/m1.eml"
        $Entries.Where({ $_.k -eq "items/$InboxKey/m3.fts" })[0].x.eml | Should -BeNullOrEmpty
        $Entries.Where({ $_.k -eq 'items/CAL/e1.fts' })[0].t | Should -Be 'event'
        $Entries.Where({ $_.k -eq 'items/CAL/e1.fts' })[0].n | Should -Be 'Subject e1'
        $Entries.Where({ $_.k -eq 'items/CON/c1.fts' })[0].n | Should -Be 'Name c1'

        ($Run.Steps | Measure-Object -Property Items -Sum).Sum | Should -Be 5
        $Run.State.Phase | Should -Be 'Folders'
        $Run.State.FolderLink | Should -BeLike '*deltatoken=F3'
        $Run.State.Folders.Where({ $_.Id -eq $InboxId })[0].Link | Should -BeLike '*deltatoken=I3'
        @($Run.State.Retry).Count | Should -Be 0
    }

    It 'only exports changes and removes deleted items on a later run' {
        $First = Invoke-Run -State $null
        $Writes.Clear()
        $Pages.Clear()
        $script:Pages['folders/delta?$deltatoken=F3'] = @{ value = @(); '@odata.deltaLink' = "$Graph/admin/exchange/mailboxes/$Mbx/folders/delta?`$deltatoken=F4" }
        $script:Pages['inbox/items/delta?$deltatoken=I3'] = @{
            value              = @(@{ id = 'm1'; '@removed' = @{ reason = 'deleted' } }, (New-MailboxItem -Id 'm4' -Second 6))
            '@odata.deltaLink' = "$Graph/x/folders/inbox/items/delta?`$deltatoken=I4"
        }
        $script:Pages['deltatoken=S1'] = @{ value = @(); '@odata.deltaLink' = "$Graph/x/folders/SUB/items/delta?`$deltatoken=S1" }
        $script:Pages['deltatoken=C1'] = @{ value = @(@{ id = 'e1'; '@removed' = @{ reason = 'deleted' } }); '@odata.deltaLink' = "$Graph/x/folders/CAL/items/delta?`$deltatoken=C2" }
        $script:Pages['deltatoken=N1'] = @{ value = @(); '@odata.deltaLink' = "$Graph/x/folders/CON/items/delta?`$deltatoken=N1" }

        $Run = Invoke-Run -State $First.State
        $Run.Done | Should -BeTrue
        $Writes.Keys | Should -Be @("items/$InboxKey/m4.fts", "items/$InboxKey/m4.eml")
        $Removes | Should -Be @("items/$InboxKey/m1.fts", "items/$InboxKey/m1.eml", 'items/CAL/e1.fts')
        $Deletes = @($Run.Steps.IndexEntries).Where({ $_.d })
        $Deletes.k | Should -Be @("items/$InboxKey/m1.fts", 'items/CAL/e1.fts')
        $Deletes.t | Should -Be @('message', 'event')
        ($Run.Steps | Measure-Object -Property Deleted -Sum).Sum | Should -Be 2
        Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*/settings/exchange' } -Times 1 -Exactly
    }

    It 'sends at most 20 items per export request and 4 requests per batch' {
        $script:Pages["folders/$([uri]::EscapeDataString($InboxId))/items/delta?`$select"] = @{
            value              = @(for ($i = 0; $i -lt 90; $i++) { New-MailboxItem -Id "b$i" -Second ($i % 60) -Class 'IPM.Contact' })
            '@odata.deltaLink' = "$Graph/x/inbox/items/delta?`$deltatoken=I3"
        }
        $null = Invoke-Run -State $null
        $InboxExports = @($ExportRequests.Where({ $_[0] -like 'b*' }))
        $InboxExports.Count | Should -Be 5
        foreach ($Ids in $InboxExports) { $Ids.Count | Should -BeLessOrEqual 20 }
        foreach ($Batch in $Batches) { @($Batch.Where({ $_.method -eq 'POST' })).Count | Should -BeLessOrEqual 4 }
    }

    It 'keeps each export batch within the size budget' {
        $script:Pages["folders/$([uri]::EscapeDataString($InboxId))/items/delta?`$select"] = @{
            value              = @(for ($i = 0; $i -lt 4; $i++) { New-MailboxItem -Id "big$i" -Second (10 + $i) -Class 'IPM.Contact' -Size 15MB })
            '@odata.deltaLink' = "$Graph/x/inbox/items/delta?`$deltatoken=I3"
        }
        $null = Invoke-Run -State $null
        $BigBatches = @($Batches.Where({ $_[0].method -eq 'POST' -and $_[0].body.itemIds[0] -like 'big*' }))
        $BigBatches.Count | Should -Be 4
        foreach ($Batch in $BigBatches) { @($Batch).Count | Should -Be 1 }
    }

    It 'pairs the .eml by change key when several messages share a creation second' {
        $Result = Save-CIPPCloudBackupExchangeItem -Context $Context -MailboxId $Mbx -FolderKey 'F' -FolderPath 'Inbox' -Items @(
            @{ Id = 'p1'; Class = 'IPM.Note'; Size = 10; Created = '2024-05-01T10:00:30Z'; Modified = '2024-05-01T10:00:30Z'; Attempts = 0 }
        )
        $Writes['items/F/p1.eml'] | Should -BeNullOrEmpty
        $Result.Failed.Id | Should -Be @('p1')

        $script:GraphObjects['2024-05-01T10:00:31Z'] = @(
            @{ id = 'G-other'; changeKey = 'CK-other'; subject = 'Other' }
            @{ id = 'G-p2'; changeKey = 'CK-p2'; subject = 'Mine' }
        )
        $script:GraphObjects['2024-05-01T10:00:32Z'] = @(@{ id = 'G-p3-newer'; changeKey = 'CK-changed-since-export'; subject = 'Only one' })
        $Result = Save-CIPPCloudBackupExchangeItem -Context $Context -MailboxId $Mbx -FolderKey 'F' -FolderPath 'Inbox' -Items @(
            @{ Id = 'p2'; Class = 'IPM.Note'; Size = 10; Created = '2024-05-01T10:00:31Z'; Modified = '2024-05-01T10:00:31Z'; Attempts = 0 }
            @{ Id = 'p3'; Class = 'IPM.Note'; Size = 10; Created = '2024-05-01T10:00:32.5000000Z'; Modified = '2024-05-01T10:00:32Z'; Attempts = 0 }
        )
        $Writes['items/F/p2.eml'] | Should -Be 'MIME:G-p2'
        $Writes['items/F/p3.eml'] | Should -Be 'MIME:G-p3-newer'
        $Result.Failed.Count | Should -Be 0
        $Result.Items | Should -Be 2
        $Result.IndexEntries.Where({ $_.k -eq 'items/F/p2.fts' })[0].n | Should -Be 'Mine'
    }

    It 'retries a failed item on the next run and gives up after three attempts' {
        $script:ExportErrors['m2'] = 'ErrorItemNotFound'
        $Run = Invoke-Run -State $null
        $Run.Done | Should -BeTrue
        @($Run.Steps.Warnings).Where({ $_ -like '*m2*ErrorItemNotFound*' }).Count | Should -Be 1
        $Run.State.Retry.Id | Should -Be @('m2')
        $Run.State.Retry[0].Attempts | Should -Be 1
        $Run.State.Folders.Where({ $_.Id -eq $InboxId })[0].Link | Should -BeLike '*deltatoken=I3'

        $script:Pages['folders/delta?$deltatoken=F3'] = @{ value = @(); '@odata.deltaLink' = "$Graph/admin/exchange/mailboxes/$Mbx/folders/delta?`$deltatoken=F3" }
        $script:Pages['deltatoken=I3'] = @{ value = @(); '@odata.deltaLink' = "$Graph/x/inbox/items/delta?`$deltatoken=I3" }
        $script:Pages['deltatoken=S1'] = @{ value = @(); '@odata.deltaLink' = "$Graph/x/SUB/items/delta?`$deltatoken=S1" }
        $script:Pages['deltatoken=C1'] = @{ value = @(); '@odata.deltaLink' = "$Graph/x/CAL/items/delta?`$deltatoken=C1" }
        $script:Pages['deltatoken=N1'] = @{ value = @(); '@odata.deltaLink' = "$Graph/x/CON/items/delta?`$deltatoken=N1" }

        $Second = Invoke-Run -State $Run.State
        $Second.State.Retry[0].Attempts | Should -Be 2
        $Third = Invoke-Run -State $Second.State
        @($Third.State.Retry).Count | Should -Be 0
        @($Third.Steps.Warnings).Where({ $_ -like 'Giving up on item m2*' }).Count | Should -Be 1

        $script:ExportErrors.Clear()
        $Writes.Clear()
        $Run2 = Invoke-Run -State $Run.State
        $Writes.Keys | Should -Contain "items/$InboxKey/m2.fts"
        $Writes.Keys | Should -Contain "items/$InboxKey/m2.eml"
        @($Run2.State.Retry).Count | Should -Be 0
    }

    It 'does not advance the folder past a page when too many items fail' {
        $script:Pages["folders/$([uri]::EscapeDataString($InboxId))/items/delta?`$select"] = @{
            value             = @(for ($i = 0; $i -lt 201; $i++) { New-MailboxItem -Id "f$i" -Second ($i % 60) -Class 'IPM.Contact' })
            '@odata.nextLink' = "$Graph/x/inbox/items/delta?`$skiptoken=I2"
        }
        for ($i = 0; $i -lt 201; $i++) { $script:ExportErrors["f$i"] = 'boom' }
        $Run = Invoke-Run -State $null
        $Run.Done | Should -BeTrue
        $Run.State.Folders.Where({ $_.Id -eq $InboxId })[0].Link | Should -BeNullOrEmpty
        @($Run.State.Retry).Count | Should -Be 0
        @($Run.Steps.Warnings).Where({ $_ -like 'Too many items failed*' }).Count | Should -Be 1
    }

    It 'removes every stored item of a deleted folder' {
        $First = Invoke-Run -State $null
        $Pages.Clear()
        $script:Pages['folders/delta?$deltatoken=F3'] = @{ value = @(@{ id = 'CAL'; '@removed' = @{ reason = 'deleted' } }); '@odata.deltaLink' = "$Graph/admin/exchange/mailboxes/$Mbx/folders/delta?`$deltatoken=F4" }
        $script:Pages['deltatoken=I3'] = @{ value = @(); '@odata.deltaLink' = "$Graph/x/inbox/items/delta?`$deltatoken=I3" }
        $script:Pages['deltatoken=S1'] = @{ value = @(); '@odata.deltaLink' = "$Graph/x/SUB/items/delta?`$deltatoken=S1" }
        $script:Pages['deltatoken=N1'] = @{ value = @(); '@odata.deltaLink' = "$Graph/x/CON/items/delta?`$deltatoken=N1" }
        Mock Get-CIPPCloudBackupObjectList {
            if ($script:Removes.Count -gt 0) { return @() }
            @([pscustomobject]@{ Key = 'policy/customer/exchange/user-1/items/CAL/e1.fts' }, [pscustomobject]@{ Key = 'policy/customer/exchange/user-1/items/CAL/e9.fts' })
        }
        $Run = Invoke-Run -State $First.State
        $Run.Done | Should -BeTrue
        $Removes | Should -Be @('items/CAL/e1.fts', 'items/CAL/e9.fts')
        Should -Invoke Get-CIPPCloudBackupObjectList -ParameterFilter { $Prefix -eq 'policy/customer/exchange/user-1/items/CAL/' }
        $Entries = @($Run.Steps.IndexEntries)
        $Entries.Where({ $_.t -eq 'folder' -and $_.d })[0].n | Should -Be 'Calendar'
        $Entries.Where({ $_.t -eq 'event' -and $_.d }).k | Should -Be @('items/CAL/e1.fts', 'items/CAL/e9.fts')
        $Run.State.Folders.Id | Should -Not -Contain 'CAL'
        @($Run.State.Removals).Count | Should -Be 0
    }

    It 'resumes from persisted state after a failed step' {
        $State = $null
        for ($i = 0; $i -lt 3; $i++) {
            $State = (Invoke-CIPPCloudBackupExchangeStep -Context $Context -State $State).State | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
        }
        $State.Phase | Should -Be 'Items'
        $script:FailGet = $true
        { Invoke-CIPPCloudBackupExchangeStep -Context $Context -State $State } | Should -Throw '*Service unavailable*'

        $script:FailGet = $false
        $GetUris.Clear()
        $Run = Invoke-Run -State $State
        $Run.Done | Should -BeTrue
        $Writes.Keys | Should -Contain 'items/CON/c1.fts'
        $GetUris.Where({ $_ -like '*folders/delta*' }).Count | Should -Be 0
        $GetUris[0] | Should -BeLike '*/items/delta?$skiptoken=I2'
    }
}

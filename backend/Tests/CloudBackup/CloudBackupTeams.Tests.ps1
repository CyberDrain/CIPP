BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup'
    Add-Type -Path (Join-Path $BackendRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $noPagination, [switch]$SkipValueExtraction, [switch]$Stream) }
    function New-GraphBulkRequest { param($tenantid, $asapp, $Requests, $Version) }
    function Write-CIPPCloudBackupItem { param($Context, $ItemKey, $Body, $Stream, $ContentType, $Metadata) }
    function Remove-CIPPCloudBackupItem { param($Context, $ItemKey) }

    . (Join-Path $Folder 'Get-CIPPCloudBackupTeamsOwner.ps1')
    . (Join-Path $Folder 'Invoke-CIPPCloudBackupTeamsStep.ps1')

    function New-TestMessage {
        param($Id, $ChatId, $ChannelId, $ReplyToId, $Content = 'hello', $Modified = '2026-11-01T10:00:00.000Z', $Deleted, $From = 'Ada')
        [pscustomobject]@{
            id                   = $Id
            replyToId            = $ReplyToId
            messageType          = 'message'
            createdDateTime      = '2026-11-01T09:00:00.000Z'
            lastModifiedDateTime = $Modified
            deletedDateTime      = $Deleted
            chatId               = $ChatId
            channelIdentity      = if ($ChannelId) { [pscustomobject]@{ teamId = 'team1'; channelId = $ChannelId } } else { $null }
            from                 = [pscustomobject]@{ user = [pscustomobject]@{ id = 'u1'; displayName = $From }; application = $null; device = $null }
            body                 = [pscustomobject]@{ contentType = 'html'; content = $Content }
        }
    }

    function New-TestContext {
        param($OwnerId = 'team1', $RunId = 'run1')
        [pscustomobject]@{ TenantFilter = 'contoso.onmicrosoft.com'; TenantId = 'tid'; PolicyId = 'p1'; Workload = 'teams'; OwnerId = $OwnerId; RunId = $RunId; RunStamp = '20261120T000000Z'; Destination = $null; KeyId = $null; Key = $null; OwnerPrefix = "p1/tid/teams/$OwnerId/" }
    }
}

Describe 'Get-CIPPCloudBackupTeamsOwner' {
    It 'returns one owner per team and one per user with an enabled Teams plan' {
        Mock New-GraphGetRequest { throw "unexpected $uri" }
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/groups?*' } {
            [pscustomobject]@{ id = 'g1'; displayName = 'Sales' }
        }
        Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/users?*' } {
            [pscustomobject]@{ id = 'u1'; displayName = 'Ada'; userPrincipalName = 'ada@contoso.com'; assignedPlans = @([pscustomobject]@{ service = 'exchange'; capabilityStatus = 'Enabled' }, [pscustomobject]@{ service = 'TeamspaceAPI'; capabilityStatus = 'Enabled' }) }
            [pscustomobject]@{ id = 'u2'; displayName = 'Bob'; userPrincipalName = 'bob@contoso.com'; assignedPlans = @([pscustomobject]@{ service = 'TeamspaceAPI'; capabilityStatus = 'Deleted' }) }
            [pscustomobject]@{ id = 'u3'; displayName = 'Cy'; userPrincipalName = 'cy@contoso.com'; assignedPlans = @() }
        }

        $Owners = @(Get-CIPPCloudBackupTeamsOwner -TenantFilter 'contoso.onmicrosoft.com')

        $Owners.Count | Should -Be 2
        $Owners[0].OwnerId | Should -Be 'g1'
        $Owners[0].OwnerType | Should -Be 'Team'
        $Owners[0].UserId | Should -BeNullOrEmpty
        $Owners[1].OwnerId | Should -Be 'u1'
        $Owners[1].OwnerType | Should -Be 'UserChats'
        $Owners[1].UserPrincipalName | Should -Be 'ada@contoso.com'
        Should -Invoke New-GraphGetRequest -ParameterFilter { $tenantid -eq 'contoso.onmicrosoft.com' } -Times 2 -Exactly
    }
}

Describe 'Invoke-CIPPCloudBackupTeamsStep' {
    BeforeEach {
        $script:Written = [System.Collections.Generic.List[object]]::new()
        $script:Version = 0
        Mock Write-CIPPCloudBackupItem {
            $script:Version++
            $script:Written.Add([pscustomobject]@{ Key = $ItemKey; Body = $Body; ContentType = $ContentType })
            [pscustomobject]@{ Key = $ItemKey; Bytes = [long]$Body.Length; VersionId = "v$script:Version"; Size = [long]$Body.Length }
        }
        Mock Remove-CIPPCloudBackupItem {}
        Mock New-GraphGetRequest { throw "unexpected GET $uri" }
        Mock New-GraphBulkRequest { throw "unexpected batch $($Requests.url -join ',')" }
        Mock New-GraphBulkRequest -ParameterFilter { $Requests[0].id -eq 'team' } {
            [pscustomobject]@{ id = 'team'; status = 200; body = [pscustomobject]@{ displayName = 'Sales' } }
            [pscustomobject]@{ id = 'channels'; status = 200; body = [pscustomobject]@{ value = @([pscustomobject]@{ id = '19:general@thread.tacv2'; displayName = 'General' }) } }
        }
    }

    Context 'channel messages for a team' {
        BeforeEach {
            Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/directoryObjects/team1*' } { [pscustomobject]@{ '@odata.type' = '#microsoft.graph.group'; id = 'team1' } }
            Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/teams/team1/channels/getAllMessages?*' } {
                [pscustomobject]@{
                    value             = @(
                        New-TestMessage -Id '100' -ChannelId '19:general@thread.tacv2' -Content '<p>Quarterly <b>numbers</b> &amp; plans</p>'
                        New-TestMessage -Id '101' -ChannelId '19:general@thread.tacv2' -ReplyToId '100'
                    )
                    '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/teams/team1/channels/getAllMessages?$skiptoken=abc'
                }
            }
            Mock New-GraphGetRequest -ParameterFilter { $uri -like '*skiptoken=abc' } {
                [pscustomobject]@{ value = @(New-TestMessage -Id '102' -ChannelId '19:gone@thread.tacv2') }
            }
        }

        It 'pages one page per step, then closes the window' {
            $First = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext) -State $null

            $First.Done | Should -BeFalse
            $First.Items | Should -Be 2
            $First.State.Kind | Should -Be 'Team'
            $First.State.NextLink | Should -BeLike '*skiptoken=abc'
            $First.State.Since | Should -BeNullOrEmpty
            $First.State.TeamName | Should -Be 'Sales'
            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter {
                $uri -like '*$top=50&$filter=lastModifiedDateTime gt 2000-01-01T00:00:00.000Z and lastModifiedDateTime lt 20*' -and $AsApp -eq $true -and $tenantid -eq 'contoso.onmicrosoft.com'
            }
            $script:Written.Key | Should -Be @('items/19:general@thread.tacv2/100.json', 'items/19:general@thread.tacv2/101.json')
            $First.IndexEntries[0].p | Should -Be 'Sales/General'
            $First.IndexEntries[0].n | Should -Be 'Ada: Quarterly numbers & plans'
            $First.IndexEntries[0].t | Should -Be 'channelMessage'
            $First.IndexEntries[0].v | Should -Be 'v1'
            $First.IndexEntries[0].d | Should -BeFalse
            $First.IndexEntries[0].x.channelId | Should -Be '19:general@thread.tacv2'
            $First.IndexEntries[0].x.createdDateTime | Should -Be '2026-11-01T09:00:00.000Z'
            $First.IndexEntries[1].x.replyToId | Should -Be '100'

            $Second = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext) -State $First.State

            $Second.Done | Should -BeTrue
            $Second.State.NextLink | Should -BeNullOrEmpty
            $Second.State.Since | Should -Be $First.State.NextSince
            $Second.State.Until | Should -BeNullOrEmpty
            $Second.IndexEntries[0].p | Should -Be 'Sales/19:gone@thread.tacv2'
            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/directoryObjects/*' }
        }

        It 'starts the next window where the last one ended and survives a JSON round trip of State' {
            $State = @{ Kind = 'Team'; Since = '2026-11-19T00:00:00.000Z'; Channels = @{ '19:general@thread.tacv2' = 'General' }; TeamName = 'Sales'; Retry = @() }
            $State = $State | ConvertTo-Json -Depth 10 | ConvertFrom-Json

            $Result = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext) -State $State

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*lastModifiedDateTime gt 2026-11-19T00:00:00.000Z and *' }
            Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*/directoryObjects/*' }
            $Round = $Result.State | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $Next = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext) -State $Round
            $Next.Done | Should -BeTrue
            $Next.State.Since | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$'
        }

        It 'throws when the first page of a window fails' {
            Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/teams/team1/channels/getAllMessages?*' } { throw 'Forbidden' }
            { Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext) -State @{ Kind = 'Team' } } | Should -Throw '*Forbidden*'
        }

        It 'keeps a failing continuation page for the next run and restarts the window after 3 failures' {
            Mock New-GraphGetRequest -ParameterFilter { $uri -like '*skiptoken=abc' } { throw 'Service unavailable' }
            $State = @{ Kind = 'Team'; Since = '2026-11-19T00:00:00.000Z'; Until = '2026-11-20T00:00:00.000Z'; NextSince = '2026-11-19T23:59:59.999Z'; NextLink = 'https://graph.microsoft.com/v1.0/teams/team1/channels/getAllMessages?$skiptoken=abc' }

            $Result = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext) -State $State
            $Result.Done | Should -BeTrue
            $Result.State.Failures | Should -Be 1
            $Result.State.NextLink | Should -BeLike '*skiptoken=abc'
            $Result.State.Since | Should -Be '2026-11-19T00:00:00.000Z'
            $Result.Warnings[0] | Should -BeLike '*Service unavailable*'

            $Result = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext) -State $Result.State
            $Result = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext) -State $Result.State
            $Result.State.NextLink | Should -BeNullOrEmpty
            $Result.State.Failures | Should -Be 0
            $Result.State.Since | Should -Be '2026-11-19T00:00:00.000Z'
        }
    }

    Context 'edits and deletions' {
        BeforeEach {
            $script:Pages = [System.Collections.Generic.Queue[object]]::new()
            Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/teams/team1/channels/getAllMessages?*' } { [pscustomobject]@{ value = @($script:Pages.Dequeue()) } }
        }

        It 'stores an edited message as a new version of the same key' {
            $script:Pages.Enqueue((New-TestMessage -Id '100' -ChannelId '19:general@thread.tacv2' -Content 'v1'))
            $script:Pages.Enqueue((New-TestMessage -Id '100' -ChannelId '19:general@thread.tacv2' -Content 'v2 edited' -Modified '2026-11-02T10:00:00.000Z'))

            $First = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext) -State @{ Kind = 'Team' }
            $Second = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext -RunId 'run2') -State $First.State

            $script:Written.Key | Should -Be @('items/19:general@thread.tacv2/100.json', 'items/19:general@thread.tacv2/100.json')
            $Second.IndexEntries[0].v | Should -Be 'v2'
            $Second.IndexEntries[0].m | Should -Be '2026-11-02T10:00:00.000Z'
            ([System.Text.Encoding]::UTF8.GetString($script:Written[1].Body) | ConvertFrom-Json).body.content | Should -Be 'v2 edited'
        }

        It 'removes a message deleted in the source and indexes it as deleted' {
            $script:Pages.Enqueue((New-TestMessage -Id '100' -ChannelId '19:general@thread.tacv2' -Content '' -Deleted '2026-11-19T12:00:00.000Z'))

            $Result = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext) -State @{ Kind = 'Team'; Since = '2026-11-19T00:00:00.000Z' }

            $Result.Deleted | Should -Be 1
            $Result.Items | Should -Be 0
            $Result.IndexEntries[0].d | Should -BeTrue
            $Result.IndexEntries[0].k | Should -Be 'items/19:general@thread.tacv2/100.json'
            Should -Invoke Remove-CIPPCloudBackupItem -Times 1 -Exactly -ParameterFilter { $ItemKey -eq 'items/19:general@thread.tacv2/100.json' -and $Context.OwnerId -eq 'team1' }
            Should -Invoke Write-CIPPCloudBackupItem -Times 0 -Exactly
        }

        It 'skips messages already deleted before the first backup' {
            $script:Pages.Enqueue((New-TestMessage -Id '100' -ChannelId '19:general@thread.tacv2' -Deleted '2026-11-19T12:00:00.000Z'))

            $Result = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext) -State @{ Kind = 'Team' }

            $Result.Deleted | Should -Be 0
            $Result.IndexEntries.Count | Should -Be 0
            Should -Invoke Remove-CIPPCloudBackupItem -Times 0 -Exactly
        }
    }

    Context 'chats for a user' {
        BeforeEach {
            Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/directoryObjects/user1*' } { [pscustomobject]@{ '@odata.type' = '#microsoft.graph.user'; id = 'user1' } }
            Mock New-GraphBulkRequest -ParameterFilter { $Requests[0].url -like '/chats/*`?$select=topic*' } {
                foreach ($Request in $Requests) {
                    $Body = if ($Request.url -like '*group@*') { [pscustomobject]@{ topic = 'Project X'; chatType = 'group' } } else { [pscustomobject]@{ topic = $null; chatType = 'oneOnOne' } }
                    [pscustomobject]@{ id = $Request.id; status = 200; body = $Body }
                }
            }
        }

        It 'backs up chat messages, names the chat and skips saved channel message copies' {
            Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/users/user1/chats/getAllMessages?*' } {
                [pscustomobject]@{ value = @(
                        New-TestMessage -Id '1' -ChatId '19:group@thread.v2'
                        New-TestMessage -Id '2' -ChatId '19:a_b@unq.gbl.spaces'
                        New-TestMessage -Id '3' -ChannelId '19:general@thread.tacv2'
                    )
                }
            }

            $Result = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext -OwnerId 'user1') -State $null

            $Result.State.Kind | Should -Be 'UserChats'
            $Result.Done | Should -BeTrue
            $Result.Items | Should -Be 2
            $script:Written.Key | Should -Be @('items/19:group@thread.v2/1.json', 'items/19:a_b@unq.gbl.spaces/2.json')
            $Result.IndexEntries[0].p | Should -Be 'Project X'
            $Result.IndexEntries[1].p | Should -Be '1:1 chat'
            $Result.IndexEntries[0].t | Should -Be 'chatMessage'
            $Result.IndexEntries[0].x.chatId | Should -Be '19:group@thread.v2'
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly -ParameterFilter { $Requests[0].id -eq 'team' }
        }

        It 'stores hosted contents next to the message' {
            $script:Content = '<p>see <img src="https://graph.microsoft.com/v1.0/chats/19:group@thread.v2/messages/1/hostedContents/aWQ9eF8w/$value"> twice <img src="https://graph.microsoft.com/v1.0/chats/19:group@thread.v2/messages/1/hostedContents/aWQ9eF8w/$value"></p>'
            Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/users/user1/chats/getAllMessages?*' } {
                [pscustomobject]@{ value = @(New-TestMessage -Id '1' -ChatId '19:group@thread.v2' -Content $script:Content) }
            }
            Mock New-GraphBulkRequest -ParameterFilter { $Requests[0].url -like '*hostedContents*' } {
                [pscustomobject]@{ id = '0'; status = 200; headers = [pscustomobject]@{ 'Content-Type' = 'image/png' }; body = [Convert]::ToBase64String([byte[]](1, 2, 3)) }
            }

            $Result = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext -OwnerId 'user1') -State @{ Kind = 'UserChats' }

            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                @($Requests).Count -eq 1 -and $Requests[0].url -eq '/chats/19:group@thread.v2/messages/1/hostedContents/aWQ9eF8w/$value' -and $Requests[0].headers.ConsistencyLevel -eq 'eventual' -and $asapp -eq $true
            }
            $Image = $script:Written.Where({ $_.Key -eq 'items/19:group@thread.v2/1/aWQ9eF8w' })[0]
            $Image.Body | Should -Be @(1, 2, 3)
            $Image.ContentType | Should -Be 'image/png'
            $Result.IndexEntries[0].x.hostedContents | Should -Be @('items/19:group@thread.v2/1/aWQ9eF8w')
            $Result.Bytes | Should -BeGreaterThan 3
        }

        It 'retries a failed message in a later run and drops it after 3 attempts' {
            Mock New-GraphGetRequest -ParameterFilter { $uri -like '*/users/user1/chats/getAllMessages?*' } {
                [pscustomobject]@{ value = @(New-TestMessage -Id '1' -ChatId '19:group@thread.v2'; New-TestMessage -Id '2' -ChatId '19:group@thread.v2') }
            }
            Mock Write-CIPPCloudBackupItem -ParameterFilter { $ItemKey -like '*/1.json' } { throw 'storage timeout' }

            $Result = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext -OwnerId 'user1') -State @{ Kind = 'UserChats' }

            $Result.Items | Should -Be 1
            $Result.Done | Should -BeTrue
            $Result.Warnings[0] | Should -BeLike '*storage timeout*'
            $Result.State.Retry.Count | Should -Be 1
            $Result.State.Retry[0].u | Should -Be '/chats/19:group@thread.v2/messages/1'
            $Result.State.Retry[0].a | Should -Be 1

            $SameRun = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext -OwnerId 'user1') -State $Result.State
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly -ParameterFilter { $Requests[0].url -like '/chats/*/messages/*' }
            $SameRun.State.Retry.Count | Should -Be 1
            $SameRun.State.Retry[0].a | Should -Be 2

            Mock New-GraphBulkRequest -ParameterFilter { $Requests[0].url -like '/chats/*/messages/*' } {
                [pscustomobject]@{ id = '0'; status = 200; body = (New-TestMessage -Id '1' -ChatId '19:group@thread.v2') }
            }
            $State = $SameRun.State | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $Retried = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext -OwnerId 'user1' -RunId 'run2') -State $State
            $Retried.Done | Should -BeFalse
            $Retried.State.Retry.Count | Should -Be 0
            $Retried.Warnings[0] | Should -BeLike '*after 3 attempts*'
        }

        It 'retries and succeeds' {
            Mock New-GraphBulkRequest -ParameterFilter { $Requests[0].url -like '/chats/*/messages/*' } {
                [pscustomobject]@{ id = '0'; status = 200; body = (New-TestMessage -Id '1' -ChatId '19:group@thread.v2') }
            }
            $State = @{ Kind = 'UserChats'; Since = '2026-11-19T00:00:00.000Z'; Retry = @(@{ u = '/chats/19:group@thread.v2/messages/1'; a = 1; r = 'run1' }) }

            $Result = Invoke-CIPPCloudBackupTeamsStep -Context (New-TestContext -OwnerId 'user1' -RunId 'run2') -State $State

            $Result.Done | Should -BeFalse
            $Result.Items | Should -Be 1
            $Result.State.Retry.Count | Should -Be 0
            $Result.State.Since | Should -Be '2026-11-19T00:00:00.000Z'
            $script:Written.Key | Should -Be @('items/19:group@thread.v2/1.json')
        }
    }
}

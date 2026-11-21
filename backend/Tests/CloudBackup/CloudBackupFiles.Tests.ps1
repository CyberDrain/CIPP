BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup'
    Add-Type -Path (Join-Path $BackendRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    function New-GraphGetRequest { param($uri, $tenantid, $asapp, $noPagination, [switch]$SkipValueExtraction) }
    function New-GraphBulkRequest { param($tenantid, $asapp, $Version, $Requests) }
    function Write-CIPPCloudBackupItem { param($Context, $ItemKey, $Body, $Stream, $ContentType, $Metadata) }
    function Remove-CIPPCloudBackupItem { param($Context, $ItemKey) }

    foreach ($Name in 'Invoke-CIPPCloudBackupDriveStep', 'Invoke-CIPPCloudBackupOneDriveStep', 'Invoke-CIPPCloudBackupSharePointStep', 'Get-CIPPCloudBackupOneDriveOwner', 'Get-CIPPCloudBackupSharePointOwner') {
        . (Join-Path $Folder "$Name.ps1")
    }

    $Probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $Probe.Start()
    $Port = $Probe.LocalEndpoint.Port
    $Probe.Stop()
    $script:BaseUrl = "http://127.0.0.1:$Port"
    $script:Seen = [hashtable]::Synchronized(@{ Auth = [System.Collections.Generic.List[string]]::new() })
    $script:Listener = [System.Net.HttpListener]::new()
    $script:Listener.Prefixes.Add("$script:BaseUrl/")
    $script:Listener.Start()
    $script:Server = [powershell]::Create()
    $null = $script:Server.AddScript({
            param($Listener, $Seen)
            $Chunk = [byte[]]::new(1MB)
            for ($i = 0; $i -lt $Chunk.Length; $i++) { $Chunk[$i] = [byte]($i % 251) }
            while ($Listener.IsListening) {
                try { $Ctx = $Listener.GetContext() } catch { break }
                $Seen.Auth.Add([string]$Ctx.Request.Headers['Authorization'])
                $Path = $Ctx.Request.Url.AbsolutePath
                if ($Path -like '/fail*') {
                    $Ctx.Response.StatusCode = 500
                    $Ctx.Response.Close()
                    continue
                }
                $Size = [int64]($Path -replace '^/size/', '')
                $Ctx.Response.ContentLength64 = $Size
                $Out = $Ctx.Response.OutputStream
                $Left = $Size
                try {
                    while ($Left -gt 0) {
                        $N = [int][Math]::Min($Left, $Chunk.Length)
                        $Out.Write($Chunk, 0, $N)
                        $Left -= $N
                    }
                    $Out.Close()
                } catch { }
            }
        }).AddArgument($script:Listener).AddArgument($script:Seen)
    $script:ServerHandle = $script:Server.BeginInvoke()

    function New-TestContext([string]$RunId = 'run1') {
        [pscustomobject]@{ TenantFilter = 'contoso.onmicrosoft.com'; TenantId = 't'; PolicyId = 'p'; Workload = 'onedrive'; OwnerId = 'user1'; RunId = $RunId; RunStamp = '20261120T000000Z'; Destination = $null; KeyId = $null; Key = $null; OwnerPrefix = 'p/c/onedrive/user1/' }
    }

    function New-DeltaFile([string]$Id, [string]$Name, [int64]$Size, [string]$Parent = 'root') {
        [pscustomobject]@{ id = $Id; name = $Name; size = $Size; eTag = "e-$Id"; webUrl = "https://contoso.sharepoint.com/$Name"; lastModifiedDateTime = '2026-11-01T00:00:00Z'; parentReference = [pscustomobject]@{ id = $Parent; driveId = 'd1' }; file = [pscustomobject]@{ mimeType = 'text/plain'; hashes = [pscustomobject]@{ quickXorHash = "h-$Id" } } }
    }

    $script:FolderLookup = {
        @(foreach ($Request in $Requests) {
                if ($Request.url -match '/items/root\?') {
                    @{ id = $Request.id; status = 200; body = [pscustomobject]@{ id = 'root'; name = 'root'; root = @{} } }
                } elseif ($Request.url -match '/items/(f\d+)\?') {
                    @{ id = $Request.id; status = 200; body = [pscustomobject]@{ id = $Matches[1]; name = "Folder$($Matches[1])"; parentReference = [pscustomobject]@{ path = '/drives/d1/root:/Docs' } } }
                } else {
                    @{ id = $Request.id; status = 404; body = [pscustomobject]@{ error = @{ message = 'not found' } } }
                }
            })
    }
}

AfterAll {
    $script:Listener.Stop()
    $script:Listener.Close()
    $script:Server.Dispose()
}

Describe 'OneDrive and SharePoint owners' {
    It 'lists members with a OneDrive and skips guests and users without one' {
        Mock New-GraphGetRequest {
            @(
                [pscustomobject]@{ id = 'u1'; displayName = 'One'; userPrincipalName = 'one@contoso.com'; userType = 'Member' }
                [pscustomobject]@{ id = 'u2'; displayName = 'Two'; userPrincipalName = 'two@contoso.com'; userType = 'Member' }
                [pscustomobject]@{ id = 'u3'; displayName = 'Guest'; userPrincipalName = 'g#EXT#@contoso.com'; userType = 'Guest' }
                [pscustomobject]@{ id = 'u4'; displayName = 'Four'; userPrincipalName = 'four@contoso.com'; userType = 'Member' }
            )
        }
        Mock New-GraphBulkRequest {
            @(
                @{ id = 'u1'; status = 200; body = @{ id = 'd1' } }
                @{ id = 'u2'; status = 404; body = @{} }
                @{ id = 'u4'; status = 503; body = @{} }
            )
        }
        $Owners = @(Get-CIPPCloudBackupOneDriveOwner -TenantFilter 'contoso.onmicrosoft.com')
        $Owners.OwnerId | Should -Be @('u1', 'u4')
        $Owners[0].UserPrincipalName | Should -Be 'one@contoso.com'
        $Owners[0].SiteUrl | Should -BeNullOrEmpty
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { @($Requests).Count -eq 3 -and $tenantid -eq 'contoso.onmicrosoft.com' }
    }

    It 'lists every non-personal site once' {
        Mock New-GraphGetRequest {
            @(
                [pscustomobject]@{ id = 's1'; displayName = 'Team'; webUrl = 'https://contoso.sharepoint.com/sites/team'; isPersonalSite = $false }
                [pscustomobject]@{ id = 's2'; displayName = 'Me'; webUrl = 'https://contoso-my.sharepoint.com/personal/me'; isPersonalSite = $true }
                [pscustomobject]@{ id = 's1'; displayName = 'Team'; webUrl = 'https://contoso.sharepoint.com/sites/team'; isPersonalSite = $false }
                [pscustomobject]@{ id = 's3'; name = 'root'; webUrl = 'https://contoso.sharepoint.com'; isPersonalSite = $false }
            )
        }
        $Owners = @(Get-CIPPCloudBackupSharePointOwner -TenantFilter 'contoso.onmicrosoft.com')
        $Owners.OwnerId | Should -Be @('s1', 's3')
        $Owners[1].DisplayName | Should -Be 'root'
        $Owners[0].SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/team'
    }
}

Describe 'OneDrive step' {
    BeforeEach {
        $script:Seen.Auth.Clear()
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Removes = [System.Collections.Generic.List[string]]::new()
        Mock Write-CIPPCloudBackupItem {
            $Buffer = [byte[]]::new(64KB)
            $Total = [int64]0
            while (($N = $Stream.Read($Buffer, 0, $Buffer.Length)) -gt 0) { $Total += $N }
            $script:Writes.Add(@{ Key = $ItemKey; Bytes = $Total; CanSeek = $Stream.CanSeek; ContentType = $ContentType; HasBody = $null -ne $Body })
            [pscustomobject]@{ Key = $ItemKey; Bytes = $Total + 116; VersionId = "v-$ItemKey"; Size = $Total }
        }
        Mock Remove-CIPPCloudBackupItem { $script:Removes.Add($ItemKey) }
        Mock New-GraphBulkRequest $script:FolderLookup
    }

    It 'enumerates in pages, streams files without the bearer token and finishes on the delta link' {
        $Base = $script:BaseUrl
        Mock New-GraphGetRequest {
            switch -Regex ($uri) {
                '/users/user1/drive\?' { [pscustomobject]@{ id = 'd1'; webUrl = 'https://contoso-my.sharepoint.com/personal/user1/Documents' } }
                'downloadUrl' {
                    $Id = ($uri -split '/items/')[1] -replace '\?.*$', ''
                    [pscustomobject]@{ id = $Id; '@microsoft.graph.downloadUrl' = "$Base/size/$(if ($Id -eq 'i1') { 1000 } else { 5 })" }
                }
                'page2' {
                    [pscustomobject]@{
                        value               = @(New-DeltaFile -Id 'i2' -Name 'b.txt' -Size 5 -Parent 'f1')
                        '@odata.deltaLink' = 'https://graph.microsoft.com/v1.0/drives/d1/root/delta?token=next'
                    }
                    break
                }
                '/root/delta\?' {
                    [pscustomobject]@{
                        value              = @(
                            [pscustomobject]@{ id = 'root'; root = @{}; folder = @{ childCount = 2 } }
                            [pscustomobject]@{ id = 'f1'; name = 'Sub'; folder = @{ childCount = 1 }; size = 5; parentReference = [pscustomobject]@{ id = 'root' }; lastModifiedDateTime = '2026-11-01T00:00:00Z' }
                            New-DeltaFile -Id 'i1' -Name 'a.txt' -Size 1000
                        )
                        '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/drives/d1/root/delta?page2'
                    }
                }
                default { throw "unexpected $uri" }
            }
        }

        $Context = New-TestContext
        $First = Invoke-CIPPCloudBackupOneDriveStep -Context $Context -State $null
        $First.Done | Should -BeFalse
        $First.Items | Should -Be 1
        $First.Bytes | Should -Be 1116
        Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*/items/i1?$select=id,content.downloadUrl' }
        $First.IndexEntries.Count | Should -Be 2
        $FolderEntry = $First.IndexEntries[0]
        $FolderEntry.t | Should -Be 'folder'
        $FolderEntry.k | Should -Be 'items/d1/f1'
        $FolderEntry.p | Should -Be '/'
        $FileEntry = $First.IndexEntries[1]
        $FileEntry.k | Should -Be 'items/d1/i1'
        $FileEntry.n | Should -Be 'a.txt'
        $FileEntry.t | Should -Be 'file'
        $FileEntry.s | Should -Be 1000
        $FileEntry.v | Should -Be 'v-items/d1/i1'
        $FileEntry.d | Should -BeFalse
        $FileEntry.x.hash | Should -Be 'h-i1'
        $FileEntry.x.driveId | Should -Be 'd1'
        $FileEntry.x.eTag | Should -Be 'e-i1'
        $script:Writes[0].CanSeek | Should -BeFalse
        $script:Writes[0].HasBody | Should -BeFalse
        $script:Writes[0].ContentType | Should -Be 'text/plain'
        $script:Seen.Auth | Should -Be @('')

        $Json = [CIPP.CippJson]::ToJson($First.State, 10)
        $Saved = $Json | ConvertFrom-Json
        $Second = Invoke-CIPPCloudBackupOneDriveStep -Context $Context -State $Saved
        $Second.Done | Should -BeTrue
        $Second.IndexEntries[0].p | Should -Be '/Docs/Folderf1'
        @($Second.State.Drives)[0].Link | Should -Be 'https://graph.microsoft.com/v1.0/drives/d1/root/delta?token=next'
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -match '/users/user1/drive\?' }
    }

    It 'resumes from the delta link on the next run and handles renames and deletes' {
        $Base = $script:BaseUrl
        Mock New-GraphGetRequest {
            switch -Regex ($uri) {
                '/users/user1/drive\?' { [pscustomobject]@{ id = 'd1' } }
                'downloadUrl' { [pscustomobject]@{ '@microsoft.graph.downloadUrl' = "$Base/size/7" } }
                'token=next' {
                    [pscustomobject]@{
                        value              = @(
                            New-DeltaFile -Id 'i1' -Name 'renamed.txt' -Size 7 -Parent 'f1'
                            [pscustomobject]@{ id = 'i2'; deleted = @{ state = 'deleted' }; parentReference = [pscustomobject]@{ id = 'f1' } }
                            [pscustomobject]@{ id = 'f9'; deleted = @{ state = 'deleted' }; folder = @{} }
                        )
                        '@odata.deltaLink' = 'https://graph.microsoft.com/v1.0/drives/d1/root/delta?token=after'
                    }
                }
                default { throw "unexpected $uri" }
            }
        }
        $State = @{ RunId = 'run1'; Drives = @(@{ Id = 'd1'; Name = 'OneDrive'; Link = 'https://graph.microsoft.com/v1.0/drives/d1/root/delta?token=next'; Complete = $true }) }
        $Result = Invoke-CIPPCloudBackupOneDriveStep -Context (New-TestContext -RunId 'run2') -State $State
        $Result.Done | Should -BeTrue
        $Result.Items | Should -Be 1
        $Result.Deleted | Should -Be 2
        $script:Writes[0].Key | Should -Be 'items/d1/i1'
        $Result.IndexEntries[0].n | Should -Be 'renamed.txt'
        $Result.IndexEntries[0].p | Should -Be '/Docs/Folderf1'
        $script:Removes | Should -Be @('items/d1/i2')
        $Result.IndexEntries[1].d | Should -BeTrue
        $Result.IndexEntries[1].t | Should -Be 'file'
        $Result.IndexEntries[2].t | Should -Be 'folder'
        $Result.IndexEntries[2].d | Should -BeTrue
        $Result.State.Drives[0].Link | Should -Be 'https://graph.microsoft.com/v1.0/drives/d1/root/delta?token=after'
    }

    It 'keeps a failed file for the next run and retries it before reading changes' {
        $Base = $script:BaseUrl
        Mock New-GraphGetRequest {
            switch -Regex ($uri) {
                '/users/user1/drive\?' { [pscustomobject]@{ id = 'd1' } }
                'items/bad\?.*downloadUrl' { [pscustomobject]@{ '@microsoft.graph.downloadUrl' = "$Base/fail" } }
                'downloadUrl' { [pscustomobject]@{ '@microsoft.graph.downloadUrl' = "$Base/size/3" } }
                'token=a' {
                    [pscustomobject]@{
                        value              = @((New-DeltaFile -Id 'bad' -Name 'bad.txt' -Size 3), (New-DeltaFile -Id 'ok' -Name 'ok.txt' -Size 3))
                        '@odata.deltaLink' = 'https://graph.microsoft.com/v1.0/drives/d1/root/delta?token=b'
                    }
                }
                'token=b' { [pscustomobject]@{ value = @(); '@odata.deltaLink' = 'https://graph.microsoft.com/v1.0/drives/d1/root/delta?token=c' } }
                default { throw "unexpected $uri" }
            }
        }
        $State = @{ RunId = 'run0'; Drives = @(@{ Id = 'd1'; Link = 'https://graph.microsoft.com/v1.0/drives/d1/root/delta?token=a'; Complete = $true }) }
        $Run1 = Invoke-CIPPCloudBackupOneDriveStep -Context (New-TestContext -RunId 'run1') -State $State
        $Run1.Done | Should -BeTrue
        $Run1.Items | Should -Be 1
        $Run1.Warnings.Count | Should -Be 1
        $Run1.Warnings[0] | Should -Match 'bad.txt'
        $Run1.State.Drives[0].Failed | Should -Be @('bad')

        Mock New-GraphBulkRequest {
            @(foreach ($Request in $Requests) {
                    if ($Request.url -match '/items/bad\?') { @{ id = 'bad'; status = 200; body = (New-DeltaFile -Id 'bad' -Name 'bad.txt' -Size 3) } }
                    else { @{ id = $Request.id; status = 200; body = [pscustomobject]@{ id = 'root'; root = @{} } } }
                })
        }
        Mock New-GraphGetRequest {
            switch -Regex ($uri) {
                '/users/user1/drive\?' { [pscustomobject]@{ id = 'd1' } }
                'downloadUrl' { [pscustomobject]@{ '@microsoft.graph.downloadUrl' = "$Base/size/3" } }
                'token=b' { [pscustomobject]@{ value = @(); '@odata.deltaLink' = 'https://graph.microsoft.com/v1.0/drives/d1/root/delta?token=c' } }
                default { throw "unexpected $uri" }
            }
        }
        $Saved = [CIPP.CippJson]::ToJson($Run1.State, 10) | ConvertFrom-Json
        $Retry = Invoke-CIPPCloudBackupOneDriveStep -Context (New-TestContext -RunId 'run2') -State $Saved
        $Retry.Done | Should -BeFalse
        $Retry.Items | Should -Be 1
        $Retry.IndexEntries[0].k | Should -Be 'items/d1/bad'
        @($Retry.State.Drives[0].Failed).Count | Should -Be 0
        $Retry.State.Drives[0].Link | Should -Be 'https://graph.microsoft.com/v1.0/drives/d1/root/delta?token=b'

        $Next = Invoke-CIPPCloudBackupOneDriveStep -Context (New-TestContext -RunId 'run2') -State $Retry.State
        $Next.Done | Should -BeTrue
        $Next.State.Drives[0].Link | Should -Be 'https://graph.microsoft.com/v1.0/drives/d1/root/delta?token=c'
    }

    It 'restarts the drive in full when the delta token has expired' {
        Mock New-GraphGetRequest {
            switch -Regex ($uri) {
                '/users/user1/drive\?' { [pscustomobject]@{ id = 'd1' } }
                'token=old' { throw 'resyncChangesApplyDifferences: Resync required' }
                default { throw "unexpected $uri" }
            }
        }
        $State = @{ RunId = 'run0'; Drives = @(@{ Id = 'd1'; Link = 'https://graph.microsoft.com/v1.0/drives/d1/root/delta?token=old'; Complete = $true }) }
        $Result = Invoke-CIPPCloudBackupOneDriveStep -Context (New-TestContext) -State $State
        $Result.Done | Should -BeFalse
        $Result.State.Drives[0].Link | Should -BeNullOrEmpty
        $Result.Warnings[0] | Should -Match 'expired'
    }

    It 'finishes with a warning when the user has no OneDrive' {
        Mock New-GraphGetRequest { throw 'Resource not found (itemNotFound)' }
        $Result = Invoke-CIPPCloudBackupOneDriveStep -Context (New-TestContext) -State $null
        $Result.Done | Should -BeTrue
        $Result.Warnings.Count | Should -Be 1
    }

    It 'streams a large file without holding it in memory' {
        $Base = $script:BaseUrl
        $Size = 256MB
        Mock New-GraphGetRequest {
            switch -Regex ($uri) {
                '/users/user1/drive\?' { [pscustomobject]@{ id = 'd1' } }
                'downloadUrl' { [pscustomobject]@{ '@microsoft.graph.downloadUrl' = "$Base/size/$Size" } }
                '/root/delta\?' { [pscustomobject]@{ value = @(New-DeltaFile -Id 'big' -Name 'big.bin' -Size $Size); '@odata.deltaLink' = 'https://graph.microsoft.com/v1.0/drives/d1/root/delta?token=x' } }
                default { throw "unexpected $uri" }
            }
        }
        $Before = [System.GC]::GetTotalAllocatedBytes($true)
        $Result = Invoke-CIPPCloudBackupOneDriveStep -Context (New-TestContext -RunId 'run9') -State @{ RunId = 'x'; Drives = @(@{ Id = 'd1'; Link = ''; Complete = $false }) }
        $Allocated = [System.GC]::GetTotalAllocatedBytes($true) - $Before
        $Result.Bytes | Should -Be ($Size + 116)
        $Allocated | Should -BeLessThan ($Size / 4)
    }
}

Describe 'SharePoint step' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        Mock Write-CIPPCloudBackupItem {
            $Buffer = [byte[]]::new(64KB)
            $Total = [int64]0
            while (($N = $Stream.Read($Buffer, 0, $Buffer.Length)) -gt 0) { $Total += $N }
            $script:Writes.Add($ItemKey)
            [pscustomobject]@{ Key = $ItemKey; Bytes = $Total; VersionId = $null; Size = $Total }
        }
        Mock Remove-CIPPCloudBackupItem { }
        Mock New-GraphBulkRequest $script:FolderLookup
    }

    It 'walks every document library of the site, one page per step, and keeps the library tokens apart' {
        $Base = $script:BaseUrl
        Mock New-GraphGetRequest {
            switch -Regex ($uri) {
                '/sites/s1/drives\?' { @([pscustomobject]@{ id = 'L1'; name = 'Documents'; webUrl = 'https://contoso.sharepoint.com/sites/s/Shared%20Documents' }, [pscustomobject]@{ id = 'L2'; name = 'Archive' }) }
                'downloadUrl' { [pscustomobject]@{ '@microsoft.graph.downloadUrl' = "$Base/size/2" } }
                'drives/L1/root/delta\?' { [pscustomobject]@{ value = @(New-DeltaFile -Id 'a' -Name 'a.docx' -Size 2); '@odata.deltaLink' = 'https://graph.microsoft.com/v1.0/drives/L1/root/delta?token=l1' } }
                'drives/L2/root/delta\?' { [pscustomobject]@{ value = @(New-DeltaFile -Id 'b' -Name 'b.docx' -Size 2); '@odata.deltaLink' = 'https://graph.microsoft.com/v1.0/drives/L2/root/delta?token=l2' } }
                default { throw "unexpected $uri" }
            }
        }
        $Context = New-TestContext
        $Context.OwnerId = 's1'
        $Context.Workload = 'sharepoint'
        $First = Invoke-CIPPCloudBackupSharePointStep -Context $Context -State $null
        $First.Done | Should -BeFalse
        $First.IndexEntries[0].x.driveName | Should -Be 'Documents'
        $Second = Invoke-CIPPCloudBackupSharePointStep -Context $Context -State $First.State
        $Second.Done | Should -BeTrue
        $script:Writes | Should -Be @('items/L1/a', 'items/L2/b')
        $Second.State.Drives.Link | Should -Be @('https://graph.microsoft.com/v1.0/drives/L1/root/delta?token=l1', 'https://graph.microsoft.com/v1.0/drives/L2/root/delta?token=l2')
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -match '/sites/s1/drives' }
    }

    It 'finishes with a warning when the site is locked' {
        Mock New-GraphGetRequest { throw 'Access to this site has been blocked.' }
        $Context = New-TestContext
        $Context.OwnerId = 's1'
        $Result = Invoke-CIPPCloudBackupSharePointStep -Context $Context -State $null
        $Result.Done | Should -BeTrue
        $Result.Warnings.Count | Should -Be 1
    }
}

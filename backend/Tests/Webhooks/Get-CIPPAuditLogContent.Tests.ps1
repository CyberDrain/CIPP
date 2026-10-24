# Pester tests for Get-CIPPAuditLogContent - listing and blob download through one request queue, the raw blob check
# and the record prefilter. A local HttpListener stands in for manage.office.com (the function is loaded with only its
# host swapped), so the queue, paging, the raw check, the parse and the rule prefilter all run.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    function Get-GraphToken { param($tenantid, $scope, $AsApp) if ($tenantid -eq 'tid-notoken') { throw 'AADSTS65001 consent missing' }; @{ Authorization = 'Bearer test' } }
    function Get-CippUserAgent { 'CIPP-Test' }
    function Get-CIPPAuditLogRuleSet { param($TenantFilter) $script:Rules }
    foreach ($Helper in 'Webhooks/Get-CIPPAuditLogPrefilter.ps1', 'Webhooks/Select-CIPPAuditLogCandidate.ps1', 'Webhooks/Get-CIPPAuditLogRuleAnchor.ps1', 'Tools/Test-CIPPConditionFilter.ps1') {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$Helper")
    }

    $script:Port = Get-Random -Minimum 20000 -Maximum 40000
    $script:Base = "http://localhost:$script:Port"
    . ([scriptblock]::Create((Get-Content (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Get-CIPPAuditLogContent.ps1') -Raw).Replace('https://manage.office.com', $script:Base)))
    $script:Files = [hashtable]::Synchronized(@{})
    $script:Listener = [System.Net.HttpListener]::new()
    $script:Listener.Prefixes.Add("http://localhost:$script:Port/")
    $script:Listener.Start()
    $script:Server = [powershell]::Create().AddScript({
            param($Listener, $Files)
            while ($Listener.IsListening) {
                try { $Context = $Listener.GetContext() } catch { break }
                # A file is the body bytes, or @{ Body; Status; Headers } for a page with a next page or an error.
                $File = $Files[$Context.Request.Url.AbsolutePath]
                if ($File -is [hashtable]) {
                    $Context.Response.StatusCode = $File.Status ?? 200
                    foreach ($Name in @($File.Headers.Keys)) { $Context.Response.Headers[$Name] = $File.Headers[$Name] }
                    $File = $File.Body
                }
                if ($File) { $Context.Response.OutputStream.Write($File, 0, $File.Length) } elseif ($Context.Response.StatusCode -eq 200) { $Context.Response.StatusCode = 404 }
                $Context.Response.Close()
            }
        }).AddArgument($script:Listener).AddArgument($script:Files)
    $null = $script:Server.BeginInvoke()

    $script:CredentialOperation = "Update application $([char]0x2013) Certificates and secrets management "
    function New-Blob([string]$TenantId, [string]$Name, [object[]]$Records) {
        $i = 0
        $Shaped = foreach ($Record in $Records) {
            $Row = [ordered]@{ Id = "$Name-$i"; Workload = 'AzureActiveDirectory' }
            if ($Record -is [string]) { $Row.Operation = $Record } else { foreach ($Key in $Record.Keys) { $Row[$Key] = $Record[$Key] } }
            $i++
            $Row
        }
        $Path = "/api/v1.0/$TenantId/activity/feed/audit/$Name"
        $script:Files[$Path] = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @($Shaped) -Compress -Depth 5))
        [pscustomobject]@{ contentUri = "$script:Base$Path"; contentId = $Name; contentType = 'Audit.AzureActiveDirectory' }
    }
    function Set-Listing([string]$TenantId, [object[]]$Blobs, [string]$Page = '', [string]$NextPage, [int]$Status = 200, [string]$Body) {
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($(if ($Body) { $Body } else { ConvertTo-Json -InputObject @($Blobs) -Compress -Depth 5 }))
        $Headers = if ($NextPage) { @{ NextPageUri = "$script:Base/api/v1.0/$TenantId/activity/feed/subscriptions/content$NextPage" + '?contentType=Audit.AzureActiveDirectory' } } else { @{} }
        $script:Files["/api/v1.0/$TenantId/activity/feed/subscriptions/content$Page"] = @{ Body = $Bytes; Status = $Status; Headers = $Headers }
    }
    function New-Query([string]$TenantId) {
        @{ TenantFilter = "$TenantId.example"; TenantId = $TenantId; ContentType = 'Audit.AzureActiveDirectory'; StartTime = [datetime]::UtcNow.AddHours(-1); EndTime = [datetime]::UtcNow }
    }
    function New-Condition([string]$Property, [string]$Operator, $Value) {
        @{ Property = @{ label = $Property; value = 'String' }; Operator = @{ label = $Operator; value = $Operator }; Input = @{ value = $Value } }
    }
    function New-Prefilter([object[][]]$RuleConditions) {
        $script:Rules = @(foreach ($Conditions in $RuleConditions) { [pscustomobject]@{ Conditions = (ConvertTo-Json -InputObject @($Conditions) -Depth 5 -Compress); Excluded = $null } })
        Get-CIPPAuditLogPrefilter -TenantFilter 'contoso.com'
    }
    function Invoke-Download($Blob, [hashtable]$Prefilters) {
        $TenantId = ([uri]$Blob.contentUri).Segments[3].TrimEnd('/')
        Set-Listing $TenantId @($Blob)
        @(Get-CIPPAuditLogContent -Queries @(New-Query $TenantId) -Prefilters $Prefilters).Where({ $_.Kind -eq 'Blob' })[0]
    }
}

AfterAll {
    $script:Listener.Stop()
    $script:Server.Dispose()
}

Describe 'Get-CIPPAuditLogContent' {
    It 'counts a threshold rule''s operations per identity and 10-minute bucket, alongside the records other rules keep' {
        $script:Rules = @(
            [pscustomobject]@{ Conditions = (ConvertTo-Json -Compress -Depth 5 -InputObject @(New-Condition 'Operation' 'in' @('FileRecycled', 'FileDeleted'))); Excluded = $null; Threshold = '{"Count":2,"Minutes":20}' }
            [pscustomobject]@{ Conditions = (ConvertTo-Json -Compress -Depth 5 -InputObject @(New-Condition 'Operation' 'eq' 'New-InboxRule')); Excluded = $null }
        )
        $Prefilter = Get-CIPPAuditLogPrefilter -TenantFilter 'contoso.com'
        $Records = @(
            @{ Operation = 'FileRecycled'; UserId = 'bob@x'; CreationTime = '2026-10-24T17:01:00' }
            @{ Operation = 'FileRecycled'; UserId = 'bob@x'; CreationTime = '2026-10-24T17:12:00' }
            @{ Operation = 'FileDeleted'; UserId = 'bob@x'; CreationTime = '2026-10-24T17:13:00' }
            'New-InboxRule'
        )
        $Result = Invoke-Download (New-Blob 'tid-t' 'deletes' $Records) @{ 'tid-t' = $Prefilter }
        $Result.Records.Id | Should -Be @('deletes-3')
        @($Result.Counts) | Should -HaveCount 1
        $Result.Counts[0].Threshold | Should -Be 0
        $Result.Counts[0].Counts['bob@x|2026-10-24T17:0'] | Should -Be 1
        $Result.Counts[0].Counts['bob@x|2026-10-24T17:1'] | Should -Be 2
        $Result.Counts[0].Index.Count | Should -Be 4
    }

    It 'lists without downloading when asked to list only' {
        Set-Listing 'tid-l1' @((New-Blob 'tid-l1' 'l1a' @('UserLoggedIn')), (New-Blob 'tid-l1' 'l1b' @('Set-Mailbox')))
        $Out = @(Get-CIPPAuditLogContent -Queries @(New-Query 'tid-l1') -ListOnly)
        $Out | Should -HaveCount 1
        $Out[0].Kind | Should -Be 'Listing'
        @($Out[0].Blobs).Count | Should -Be 2
        $Out[0].Complete | Should -BeTrue
        $Out[0].TenantDone | Should -BeTrue
    }

    It 'downloads the blobs it is given, of several tenants, without listing, and hands back what rode along' {
        $Given = foreach ($Tenant in 'tid-g1', 'tid-g2') {
            foreach ($n in 1..2) {
                $Blob = New-Blob $Tenant "$Tenant-$n" @('UserLoggedIn', 'Set-Mailbox')
                [pscustomobject]@{ TenantId = $Tenant; contentUri = $Blob.contentUri; RowKey = "row-$Tenant-$n" }
            }
        }
        $Out = @(Get-CIPPAuditLogContent -Blobs @($Given) -MaxConcurrency 2)
        $Out | Should -HaveCount 4
        @($Out.Where({ $_.Kind -ne 'Blob' })) | Should -HaveCount 0
        @($Out.Blob.RowKey | Sort-Object) | Should -Be @('row-tid-g1-1', 'row-tid-g1-2', 'row-tid-g2-1', 'row-tid-g2-2')
        @($Out.Where({ $_.TenantDone }).TenantId | Sort-Object) | Should -Be @('tid-g1', 'tid-g2')
        @($Out.Records).Count | Should -Be 8
    }

    It 'keeps the records a like or eq rule matches, case-insensitively' {
        $Prefilter = New-Prefilter @(, @(New-Condition 'Operation' 'like' 'update application*certificates and secrets management*')), @(, @(New-Condition 'Operation' 'eq' 'userloggedin'))
        $Result = Invoke-Download (New-Blob 'tid-1' 'mixed' @($script:CredentialOperation, 'Update application.', 'UserLoggedIn', 'Set-Mailbox')) @{ 'tid-1' = $Prefilter }
        $Result.Skipped | Should -BeFalse
        $Result.RecordCount | Should -Be 4
        $Result.Records.Id | Should -Be @('mixed-0', 'mixed-2')
    }

    It 'skips a blob without the text before a pattern''s first wildcard, unparsed' {
        $Prefilter = New-Prefilter @(, @(New-Condition 'Operation' 'like' 'Update application*Certificates and secrets management*'))
        $Result = Invoke-Download (New-Blob 'tid-1' 'signins' @('UserLoggedIn', 'UserLoginFailed')) @{ 'tid-1' = $Prefilter }
        $Result.Skipped | Should -BeTrue
        $Result.RecordCount | Should -Be 0
    }

    It 'checks a pattern that starts with a wildcard by its text anywhere in the blob, and still keeps only matches' {
        $Prefilter = New-Prefilter @(, @(New-Condition 'Operation' 'like' '*principal credentials.'))
        $Result = Invoke-Download (New-Blob 'tid-1' 'leading' @('UserLoggedIn', 'Add service principal credentials.')) @{ 'tid-1' = $Prefilter }
        $Result.Skipped | Should -BeFalse
        $Result.Records.Id | Should -Be @('leading-1')
        (Invoke-Download (New-Blob 'tid-1' 'other' @('UserLoggedIn', 'Add service principal.')) @{ 'tid-1' = $Prefilter }).Skipped | Should -BeTrue
    }

    It 'does not skip a blob holding an item named Operation, which the engine flattens over the record''s own' {
        $Prefilter = New-Prefilter @(, @(New-Condition 'Operation' 'eq' 'New-InboxRule'))
        $Shadowed = @{ Operation = 'Set-Mailbox'; parameters = @(@{ Name = 'Operation'; Value = 'New-InboxRule' }) }
        $Result = Invoke-Download (New-Blob 'tid-1' 'shadow' @($Shadowed, 'Set-Mailbox')) @{ 'tid-1' = $Prefilter }
        $Result.Skipped | Should -BeFalse
        $Result.Records.Id | Should -Be @('shadow-0')
    }

    It 'skips every blob when the only rule has no anchor, since the engine skips that rule' {
        $Prefilter = New-Prefilter @(, @(New-Condition 'UserId' 'like' 'ServicePrincipal_*'))
        $Result = Invoke-Download (New-Blob 'tid-1' 'actors' @(@{ Operation = 'Add owner to application.'; UserId = 'ServicePrincipal_1' })) @{ 'tid-1' = $Prefilter }
        $Result.Skipped | Should -BeTrue
    }

    It 'keeps every record for a tenant with no prefilter' {
        $Result = Invoke-Download (New-Blob 'tid-2' 'open' @('UserLoggedIn', 'Set-Mailbox')) @{ 'tid-2' = $null }
        $Result.Records.Count | Should -Be 2
    }

    It 'skips every blob for a tenant no rule covers' {
        $script:Rules = @()
        $Result = Invoke-Download (New-Blob 'tid-3' 'none' @('UserLoggedIn')) @{ 'tid-3' = (Get-CIPPAuditLogPrefilter -TenantFilter 'contoso.com') }
        $Result.Skipped | Should -BeTrue
    }

    It 'follows NextPageUri, downloads the blobs of every page and emits each page as it is read, the last one Complete' {
        Set-Listing 'tid-4' @(New-Blob 'tid-4' 'p1' @('UserLoggedIn')) -NextPage '/page2'
        Set-Listing 'tid-4' @(New-Blob 'tid-4' 'p2' @('Set-Mailbox')) -Page '/page2'
        $Out = @(Get-CIPPAuditLogContent -Queries @(New-Query 'tid-4') -Prefilters @{ 'tid-4' = $null })
        $Listings = @($Out.Where({ $_.Kind -eq 'Listing' }))
        $Listings | Should -HaveCount 2
        $Listings[0].Blobs.contentId | Should -Be @('p1')
        $Listings[0].Complete | Should -BeFalse
        $Listings[0].TenantDone | Should -BeFalse
        $Listings[1].Blobs.contentId | Should -Be @('p2')
        $Listings[1].Complete | Should -BeTrue
        (@($Out.Where({ $_.Kind -eq 'Blob' })).Records.Id | Sort-Object) | Should -Be @('p1-0', 'p2-0')
        @($Out.Where({ $_.TenantDone })) | Should -HaveCount 1
        $Out[-1].TenantDone | Should -BeTrue
    }

    It 'marks each tenant done once, on its last object, with several tenants in one stream' {
        Set-Listing 'tid-5' @((New-Blob 'tid-5' 'a' @('UserLoggedIn')), (New-Blob 'tid-5' 'b' @('UserLoggedIn')))
        Set-Listing 'tid-6' @(New-Blob 'tid-6' 'c' @('UserLoggedIn'))
        $Out = @(Get-CIPPAuditLogContent -Queries @((New-Query 'tid-5'), (New-Query 'tid-6')) -Prefilters @{} -MaxConcurrency 2)
        $Out | Should -HaveCount 5
        foreach ($TenantId in 'tid-5', 'tid-6') {
            $Mine = @($Out.Where({ [string]$_.TenantId -eq $TenantId }))
            @($Mine.Where({ $_.TenantDone })) | Should -HaveCount 1
            $Mine[-1].TenantDone | Should -BeTrue
        }
    }

    It 'reports a listing error with its AF code and downloads nothing for it' {
        Set-Listing 'tid-7' -Status 403 -Body '{"error":{"code":"AF429","message":"Too many requests."}}'
        $Out = @(Get-CIPPAuditLogContent -Queries @(New-Query 'tid-7') -Prefilters @{})
        $Out | Should -HaveCount 1
        $Out[0].Kind | Should -Be 'Listing'
        $Out[0].ErrorCode | Should -Be 'AF429'
        $Out[0].Error | Should -Be 'Too many requests.'
        $Out[0].StatusCode | Should -Be 403
        $Out[0].TenantDone | Should -BeTrue
    }

    It 'reports a tenant without a token as Token, alongside a tenant that works' {
        Set-Listing 'tid-8' @(New-Blob 'tid-8' 'ok' @('UserLoggedIn'))
        $Out = @(Get-CIPPAuditLogContent -Queries @((New-Query 'tid-notoken'), (New-Query 'tid-8')) -Prefilters @{})
        $Failed = $Out.Where({ $_.TenantId -eq 'tid-notoken' })[0]
        $Failed.ErrorCode | Should -Be 'Token'
        $Failed.Error | Should -Match 'consent missing'
        $Failed.TenantDone | Should -BeTrue
        $Out.Where({ $_.Kind -eq 'Blob' })[0].Records.Id | Should -Be @('ok-0')
    }
}

BeforeAll {
    Get-ChildItem "$PSScriptRoot/../../Modules/CippExtensions/Private/Documentation/*.ps1", "$PSScriptRoot/../../Modules/CippExtensions/Private/Hudu/*.ps1" | ForEach-Object { . $_.FullName }

    $script:SyncedAt = [datetime]::new(2026, 10, 20, 12, 0, 0, [System.DateTimeKind]::Utc)

    function New-TestLicenseModel {
        [ordered]@{
            Name            = 'Microsoft 365 Business Premium'
            SkuId           = 'cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46'
            Status          = 'Active'
            StatusTone      = 'ok'
            AdminUrl        = 'https://admin.microsoft.com/Partner/BeginClientSession.aspx?CTID=11111111-2222-4333-8444-555555555555&CSDEST=o365admincenter/Adminportal/Home#/licenses'
            CippUrl         = 'https://cipp.example/tenant/reports/list-licenses?tenantFilter=fabrikam.example'
            PurchasedText   = '10'
            UsedText        = '6'
            FreeText        = '4'
            UsedPercent     = '60'
            UsedPercentText = '60%'
            UsageTone       = 'ok'
            RenewalDate     = '15 Dec 2026'
            Subscriptions   = @(
                [ordered]@{ Term = 'Monthly'; Status = 'Enabled'; StatusTone = 'ok'; IsTrial = $false; SeatsText = '2'; TermEnds = '15 Dec 2026' }
                [ordered]@{ Term = 'Yearly'; Status = 'Enabled'; StatusTone = 'ok'; IsTrial = $false; SeatsText = '8'; TermEnds = '1 Mar 2027' }
            )
            Users           = @(
                [ordered]@{ Name = 'Ada Lovelace'; Address = 'ada@fabrikam.example'; Url = 'https://hudu.example/a/1' }
                [ordered]@{ Name = 'Grace Hopper'; Address = 'grace@fabrikam.example'; Url = '' }
            )
            Attention       = @()
        }
    }
}

Describe 'Get-HuduLicenseBody' {
    It 'renders every section for a full model' {
        $Body = Get-HuduLicenseBody -Model (New-TestLicenseModel) -SyncedAt $script:SyncedAt
        foreach ($Text in 'Microsoft 365 Business Premium', '>Active<', 'cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46', 'Synced 20 Oct 2026 12:00 UTC', '>Seats</span></h3>', '>Subscriptions ', '>Assigned users ',
            'of 10 assigned', '15 Dec 2026', '1 Mar 2027', '>Yearly<', 'https://hudu.example/a/1', 'grace@fabrikam.example',
            'https://cipp.example/tenant/reports/list-licenses?tenantFilter=fabrikam.example', 'CTID=11111111-2222-4333-8444-555555555555') {
            $Body | Should -Match ([regex]::Escape($Text))
        }
        $Body | Should -Match 'width:60%;background:#f77f00'
        $Body | Should -Not -Match 'Needs attention'
    }

    It 'leaves out the sync time, and the subscription and user cards when they are empty' {
        $Model = New-TestLicenseModel
        $Model.Subscriptions = @(); $Model.Users = @()
        $Body = Get-HuduLicenseBody -Model $Model
        $Body | Should -Not -Match '>Subscriptions |>Assigned users |>Synced '
    }

    It 'shows the attention strip and marks a trial subscription' {
        $Model = New-TestLicenseModel
        $Model.Attention = @('A subscription is **suspended**')
        $Model.Subscriptions[0].IsTrial = $true
        $Body = Get-HuduLicenseBody -Model $Model
        $Body | Should -Match 'Needs attention'
        $Body | Should -Match 'A subscription is <strong>suspended</strong>'
        $Body | Should -Match '>Trial<'
    }

    It 'uses nothing the Hudu sanitizer strips and the brand header' {
        $Body = Get-HuduLicenseBody -Model (New-TestLicenseModel) -SyncedAt $script:SyncedAt
        $Body | Should -Not -Match 'gap:|<svg|aria-hidden'
        $Body | Should -Match '^<div style="overflow:hidden"><div style="border:1px solid rgba\(128,128,128,.3\);border-top:3px solid #f77f00;'
    }

    It 'encodes names from the tenant' {
        $Model = New-TestLicenseModel
        $Model.Name = 'Evil <script>alert(1)</script>'
        $Model.Users[1].Name = '<b>Grace</b>'
        $Body = Get-HuduLicenseBody -Model $Model
        $Body | Should -Not -Match '<script>|<b>Grace'
        $Body | Should -Match '&lt;script&gt;'
    }
}

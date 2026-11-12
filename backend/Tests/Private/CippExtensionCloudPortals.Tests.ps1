# Extension documentation (Hudu, NinjaOne) links to Microsoft portals follow a government tenant's cloud
# (redanthrax/CIPP#4). A Commercial tenant, or one without a stored cloud, gets exactly the links it got before.

BeforeAll {
    Get-ChildItem "$PSScriptRoot/../../Modules/CippExtensions/Private/Documentation/*.ps1", "$PSScriptRoot/../../Modules/CippExtensions/Private/Hudu/*.ps1" | ForEach-Object { . $_.FullName }
    . "$PSScriptRoot/../../Modules/CIPPCore/Public/GraphHelper/ConvertTo-CIPPCloudPortalUrl.ps1"
    $script:PreviousRoot = $env:CIPPRootPath
    $env:CIPPRootPath = (Resolve-Path "$PSScriptRoot/../..").Path

    $script:User = [PSCustomObject]@{ id = 'u1'; displayName = 'Ada'; userPrincipalName = 'ada@gov.example'; accountEnabled = $true }
    $script:Device = [PSCustomObject]@{ id = 'dev-1'; deviceName = 'LAPTOP-1'; complianceState = 'compliant'; operatingSystem = 'Windows'; lastSyncDateTime = '2026-10-19T00:00:00Z' }
    function script:New-Tenant([string]$Cloud) {
        $Tenant = [PSCustomObject]@{ displayName = 'Gov'; defaultDomainName = 'gov.example'; customerId = 'g1' }
        if ($Cloud) { $Tenant | Add-Member -NotePropertyName cloudEnvironment -NotePropertyValue $Cloud }
        $Tenant
    }
}

AfterAll { $env:CIPPRootPath = $script:PreviousRoot }

Describe 'Extension view model portal links' {
    BeforeEach { $script:CIPPCloudPortalHosts = $null }

    It 'keeps the commercial user links for cloud <Name>' -TestCases @(@{ Name = 'Commercial'; Cloud = 'Commercial' }, @{ Name = 'none'; Cloud = '' }) {
        param($Name, $Cloud)
        $Model = Get-CippExtensionUserViewModel -User $script:User -Tenant (script:New-Tenant $Cloud) -Devices @($script:Device) -EnableCIPP $false
        @($Model.Links.Microsoft.Label) | Should -Be @('Entra ID', 'Sign-ins', 'Teams Admin', 'Intune (User)', 'Intune (Devices)')
        $Model.Links.Microsoft[0].Url | Should -BeExactly 'https://entra.microsoft.com/gov.example/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/u1'
        $Model.Devices.Items[0].Url | Should -BeLike 'https://intune.microsoft.com/gov.example/*'
    }

    It 're-points a GCC High user''s links and leaves out Teams admin' {
        $Model = Get-CippExtensionUserViewModel -User $script:User -Tenant (script:New-Tenant 'USGovHigh') -Devices @($script:Device) -EnableCIPP $false
        @($Model.Links.Microsoft.Label) | Should -Be @('Entra ID', 'Sign-ins', 'Intune (User)', 'Intune (Devices)')
        $Model.Links.Microsoft[0].Url | Should -BeExactly 'https://entra.microsoft.us/gov.example/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/u1'
        $Model.Links.Microsoft[2].Url | Should -BeLike 'https://intune.microsoft.us/gov.example/*'
        $Model.Devices.Items[0].Url | Should -BeLike 'https://intune.microsoft.us/gov.example/*'
    }

    It 're-points the device model''s Intune link only for a government tenant' {
        (Get-CippExtensionDeviceViewModel -Device $script:Device -Tenant (script:New-Tenant 'Commercial')).Links.Microsoft[0].Url | Should -BeLike 'https://intune.microsoft.com/gov.example/*'
        (Get-CippExtensionDeviceViewModel -Device $script:Device -Tenant (script:New-Tenant 'USGovDoD')).Links.Microsoft[0].Url | Should -BeLike 'https://intune.microsoft.us/gov.example/*'
    }

    It 'points the magic dash people links at the government Entra and drops the M365 admin link' {
        $Users = @([PSCustomObject]@{ id = 'u1'; displayName = 'Ada'; userPrincipalName = 'ada@gov.example'; Licenses = @('E5'); Devices = @() })
        $Com = (Get-HuduMagicDashViewModel -Tenant (script:New-Tenant 'Commercial') -Users $Users).People[0]
        $Com.EntraUrl | Should -BeExactly 'https://entra.microsoft.com/gov.example/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/u1'
        $Com.AdminUrl | Should -BeLike 'https://admin.microsoft.com/Partner/*'
        $Gov = (Get-HuduMagicDashViewModel -Tenant (script:New-Tenant 'USGovHigh') -Users $Users).People[0]
        $Gov.EntraUrl | Should -BeExactly 'https://entra.microsoft.us/gov.example/#blade/Microsoft_AAD_IAM/UserDetailsMenuBlade/Profile/userId/u1'
        $Gov.AdminUrl | Should -BeNullOrEmpty
    }
}

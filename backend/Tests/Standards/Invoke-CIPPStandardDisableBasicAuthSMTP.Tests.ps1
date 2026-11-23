# Pester tests for Invoke-CIPPStandardDisableBasicAuthSMTP
#
# The standard reads its state from the report cache. A remediating run used to report the state
# it found and leave the cache alone, so the compare row and every later run until the nightly
# collection still saw the old values: drift stayed open and the same writes were repeated.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardDisableBasicAuthSMTP.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardDisableBasicAuthSMTP.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-CIPPDbRequest { [CmdletBinding()] param($TenantFilter, $Type, $Fields) }
    function New-ExoRequest { [CmdletBinding()] param($cmdlet, $cmdParams, $Select, $Anchor, $useSystemMailbox, $tenantid, $NoAuthCheck, $Compliance, $AsApp) }
    function New-ExoBulkRequest { [CmdletBinding()] param($tenantid, $cmdletArray, $useSystemMailbox, $Anchor, $NoAuthCheck, $Select) }
    function Set-CIPPDBCacheExoTransportConfig { [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantFilter, [string]$QueueId) }
    function Set-CIPPDBCacheCASMailboxes { [CmdletBinding()] param([Parameter(Mandatory)][string]$TenantFilter, [string]$QueueId) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue, $TenantFilter, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }

    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:AllModes = @{ remediate = $true; alert = $true; report = $true }

    function script:New-CasMailbox {
        param([string]$Guid, [string]$Address, $SmtpDisabled = $false)
        [pscustomobject]@{ Guid = $Guid; PrimarySmtpAddress = $Address; SmtpClientAuthenticationDisabled = $SmtpDisabled }
    }
}

Describe 'Invoke-CIPPStandardDisableBasicAuthSMTP' {
    BeforeEach {
        $script:logs = [System.Collections.Generic.List[object]]::new()
        $script:alerts = [System.Collections.Generic.List[object]]::new()
        $script:compare = [System.Collections.Generic.List[object]]::new()
        $script:bulk = $null
        $script:transportDisabled = $false
        $script:casMailboxes = @(
            New-CasMailbox -Guid 'guid-a' -Address 'a@contoso.com'
            New-CasMailbox -Guid 'guid-b' -Address 'b@contoso.com'
            New-CasMailbox -Guid 'guid-c' -Address 'c@contoso.com' -SmtpDisabled $null
        )
        # Mailbox guids the bulk Set-CASMailbox should answer with an error.
        $script:failGuids = @()

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Write-LogMessage -MockWith {
            param($API, $tenant, $message, $sev)
            $script:logs.Add(@{ Message = $message; Sev = $sev })
        }
        Mock -CommandName Write-StandardsAlert -MockWith {
            param($message, $object)
            $script:alerts.Add(@{ Message = $message; Object = $object })
        }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith {
            param($FieldName, $FieldValue, $CurrentValue, $ExpectedValue)
            $script:compare.Add(@{ Current = $CurrentValue; Expected = $ExpectedValue })
        }
        Mock -CommandName New-CIPPDbRequest -MockWith {
            param($TenantFilter, $Type)
            if ($Type -eq 'ExoTransportConfig') { [pscustomobject]@{ SmtpClientAuthenticationDisabled = $script:transportDisabled } } else { $script:casMailboxes }
        }
        Mock -CommandName New-ExoRequest -MockWith { }
        # Mirrors New-ExoBulkRequest: with an OperationGuid a write answers Success or error per item.
        Mock -CommandName New-ExoBulkRequest -MockWith {
            param($tenantid, $cmdletArray)
            $script:bulk = $cmdletArray
            foreach ($Item in $cmdletArray) {
                if ($script:failGuids -contains $Item.OperationGuid) {
                    [pscustomobject]@{ error = 'Access denied'; target = $Item.OperationGuid; OperationGuid = $Item.OperationGuid }
                } else {
                    [pscustomobject]@{ Success = $true; OperationGuid = $Item.OperationGuid }
                }
            }
        }
        Mock -CommandName Set-CIPPDBCacheExoTransportConfig -MockWith { }
        Mock -CommandName Set-CIPPDBCacheCASMailboxes -MockWith { }
    }

    Context 'remediation' {
        It 'reports the post-remediation state and refreshes both caches once' {
            Invoke-CIPPStandardDisableBasicAuthSMTP -Tenant $script:Tenant -Settings $script:AllModes

            Should -Invoke -CommandName New-ExoRequest -Times 1 -Exactly -ParameterFilter { $cmdlet -eq 'Set-TransportConfig' -and $cmdParams.SmtpClientAuthenticationDisabled -eq $true }
            @($script:bulk.CmdletInput.Parameters.Identity) | Should -Be @('guid-a', 'guid-b')
            $script:compare.Count | Should -Be 1
            $script:compare[0].Current.SmtpClientAuthenticationDisabled | Should -BeTrue
            @($script:compare[0].Current.UsersWithSmtpAuthEnabled) | Should -BeNullOrEmpty
            $script:alerts.Count | Should -Be 0
            Should -Invoke -CommandName Set-CIPPDBCacheExoTransportConfig -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq $script:Tenant }
            Should -Invoke -CommandName Set-CIPPDBCacheCASMailboxes -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq $script:Tenant }
        }

        It 'keeps a mailbox it failed to change in the report' {
            $script:failGuids = @('guid-b')

            Invoke-CIPPStandardDisableBasicAuthSMTP -Tenant $script:Tenant -Settings $script:AllModes

            @($script:compare[0].Current.UsersWithSmtpAuthEnabled) | Should -Be @('b@contoso.com')
            $script:compare[0].Current.SmtpClientAuthenticationDisabled | Should -BeTrue
            $script:alerts.Count | Should -Be 1
            $script:alerts[0].Object.UsersWithSMTPAuthEnabled | Should -Be 1
            Should -Invoke -CommandName Set-CIPPDBCacheCASMailboxes -Times 1 -Exactly
        }

        It 'leaves the mailbox cache alone when every mailbox write fails' {
            $script:failGuids = @('guid-a', 'guid-b')

            Invoke-CIPPStandardDisableBasicAuthSMTP -Tenant $script:Tenant -Settings $script:AllModes

            @($script:compare[0].Current.UsersWithSmtpAuthEnabled) | Should -Be @('a@contoso.com', 'b@contoso.com')
            Should -Invoke -CommandName Set-CIPPDBCacheCASMailboxes -Times 0 -Exactly
            Should -Invoke -CommandName Set-CIPPDBCacheExoTransportConfig -Times 1 -Exactly
        }

        It 'still reports the tenant as not disabled when Set-TransportConfig fails' {
            Mock -CommandName New-ExoRequest -MockWith { throw 'Exchange said no' }

            Invoke-CIPPStandardDisableBasicAuthSMTP -Tenant $script:Tenant -Settings $script:AllModes

            $script:compare[0].Current.SmtpClientAuthenticationDisabled | Should -BeFalse
            @($script:compare[0].Current.UsersWithSmtpAuthEnabled) | Should -BeNullOrEmpty
            $script:alerts.Count | Should -Be 1
            Should -Invoke -CommandName Set-CIPPDBCacheExoTransportConfig -Times 0 -Exactly
            Should -Invoke -CommandName Set-CIPPDBCacheCASMailboxes -Times 1 -Exactly
        }

        It 'does not refresh the transport cache when only mailboxes needed changing' {
            $script:transportDisabled = $true

            Invoke-CIPPStandardDisableBasicAuthSMTP -Tenant $script:Tenant -Settings $script:AllModes

            Should -Invoke -CommandName Set-CIPPDBCacheExoTransportConfig -Times 0 -Exactly
            Should -Invoke -CommandName Set-CIPPDBCacheCASMailboxes -Times 1 -Exactly
        }

        It 'writes and refreshes nothing when the tenant is already compliant' {
            $script:transportDisabled = $true
            $script:casMailboxes = @(New-CasMailbox -Guid 'guid-c' -Address 'c@contoso.com' -SmtpDisabled $null)

            Invoke-CIPPStandardDisableBasicAuthSMTP -Tenant $script:Tenant -Settings $script:AllModes

            Should -Invoke -CommandName New-ExoRequest -Times 0 -Exactly
            Should -Invoke -CommandName New-ExoBulkRequest -Times 0 -Exactly
            Should -Invoke -CommandName Set-CIPPDBCacheExoTransportConfig -Times 0 -Exactly
            Should -Invoke -CommandName Set-CIPPDBCacheCASMailboxes -Times 0 -Exactly
            $script:compare[0].Current.SmtpClientAuthenticationDisabled | Should -BeTrue
            $script:alerts.Count | Should -Be 0
        }

        It 'logs a warning and still reports when a cache refresh throws' {
            Mock -CommandName Set-CIPPDBCacheExoTransportConfig -MockWith { throw 'table unavailable' }
            Mock -CommandName Set-CIPPDBCacheCASMailboxes -MockWith { throw 'table unavailable' }

            { Invoke-CIPPStandardDisableBasicAuthSMTP -Tenant $script:Tenant -Settings $script:AllModes } | Should -Not -Throw

            @($script:logs | Where-Object { $_.Sev -eq 'Warning' -and $_.Message -like '*cache after remediation: table unavailable' }).Count | Should -Be 2
            $script:compare.Count | Should -Be 1
            $script:compare[0].Current.SmtpClientAuthenticationDisabled | Should -BeTrue
        }
    }

    Context 'report and alert only' {
        It 'reports what the cache holds without writing or refreshing' {
            Invoke-CIPPStandardDisableBasicAuthSMTP -Tenant $script:Tenant -Settings @{ alert = $true; report = $true }

            Should -Invoke -CommandName New-ExoRequest -Times 0 -Exactly
            Should -Invoke -CommandName New-ExoBulkRequest -Times 0 -Exactly
            Should -Invoke -CommandName Set-CIPPDBCacheExoTransportConfig -Times 0 -Exactly
            Should -Invoke -CommandName Set-CIPPDBCacheCASMailboxes -Times 0 -Exactly
            $script:compare[0].Current.SmtpClientAuthenticationDisabled | Should -BeFalse
            @($script:compare[0].Current.UsersWithSmtpAuthEnabled) | Should -Be @('a@contoso.com', 'b@contoso.com')
            $script:alerts.Count | Should -Be 1
        }
    }
}

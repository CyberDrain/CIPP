# JIT Admin keeps its state in the cippUser schema extension that Get-CIPPSchemaExtensions registers in the partner
# tenant's cloud (redanthrax/CIPP#4). A GCC High / DoD direct tenant of a commercial partner does not have it, so
# the JIT paths must refuse or skip that tenant before reading the extension, and must behave exactly as before for
# Commercial tenants, AllTenants and a government tenant in the partner's own cloud.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPTenantRequestCloud { param($TenantFilter) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CIPPSchemaExtensions { param([switch]$Update, $Headers) }
    function New-GraphBulkRequest { param($tenantid, $Requests) }
    function New-GraphGetRequest { param($uri, $tenantid, [switch]$ComplexFilter, $AsApp, $ErrorAction) }
    function New-GraphPOSTRequest { param($type, $Uri, $Body, $tenantid) }
    function Get-CIPPJITAdminAllowedRoles { param($Headers) [pscustomobject]@{ Restricted = $false } }
    function Get-CIPPJITAdminApprovalRequirement { param($Roles, $TenantFilter) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Update-AzDataTableEntity { param($TableName, $Entity) }
    function Add-CIPPScheduledTask { param($Task, $hidden, [switch]$RunNow) }
    function Get-CIPPMFAStateReport { param($TenantFilter) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    $Modules = Join-Path $RepoRoot 'Modules'
    . (Join-Path $Modules 'CIPPCore/Public/GraphHelper/Get-CIPPPartnerCloudEnvironment.ps1')
    . (Join-Path $Modules 'CIPPCore/Public/Functions/Get-CIPPCloudFeatureSupport.ps1')
    . (Join-Path $Modules 'CIPPCore/Public/Get-CIPPJITAdminCloudError.ps1')
    . (Join-Path $Modules 'CIPPCore/Public/Functions/Test-IsGuid.ps1')
    . (Join-Path $Modules 'CIPPCore/Public/Set-CIPPUserJITAdmin.ps1')
    . (Join-Path $Modules 'CIPPCore/Public/Set-CIPPUserJITAdminProperties.ps1')
    . (Join-Path $Modules 'CIPPAlerts/Public/Alerts/Get-CIPPAlertMFAAdmins.ps1')
    foreach ($Name in 'Invoke-ListJITAdmin.ps1', 'Invoke-ExecJITAdmin.ps1', 'Push-ExecJITAdminListAllTenants.ps1') {
        . (Get-ChildItem -Path $Modules -Recurse -Filter $Name | Select-Object -First 1).FullName
    }

    $script:PreviousRoot = $env:CIPPRootPath
    $script:PreviousPartnerCloud = $env:CIPP_PARTNER_CLOUD
    $env:CIPPRootPath = $RepoRoot

    $script:Clouds = @{ 'contoso.com' = 'Commercial'; 'gov.us' = 'USGovHigh'; 'dod.mil' = 'USGovDoD' }
    $script:Schema = [pscustomobject]@{ id = 'extabc_cippUser' }

    function New-ExecRequest {
        param([string]$Tenant)
        $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"admin@contoso.com"}'))
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecJITAdmin' }
            Headers = @{ 'x-ms-client-principal' = $Principal }
            Body    = [pscustomobject]@{
                tenantFilter  = [pscustomobject]@{ value = $Tenant }
                userAction    = 'existing'
                existingUser  = [pscustomobject]@{ value = "jit@$Tenant" }
                AdminRoles    = @([pscustomobject]@{ value = '62e90394-69f5-4237-9190-012177145e10' })
                ExpireAction  = [pscustomobject]@{ value = 'RemoveRoles' }
                Reason        = 'Break glass'
                StartDate     = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                EndDate       = [DateTimeOffset]::UtcNow.AddDays(1).ToUnixTimeSeconds()
            }
        }
    }
}

AfterAll {
    $env:CIPPRootPath = $script:PreviousRoot
    $env:CIPP_PARTNER_CLOUD = $script:PreviousPartnerCloud
}

Describe 'JIT Admin for government tenants' {
    BeforeEach {
        $env:CIPP_PARTNER_CLOUD = $null
        $script:CIPPCloudFeatureSupport = $null
        Mock Get-CIPPTenantRequestCloud { $script:Clouds[$TenantFilter] }
        Mock Get-CIPPSchemaExtensions { $script:Schema }
        Mock New-GraphBulkRequest { }
        Mock New-GraphPOSTRequest { }
        Mock Add-CIPPAzDataTableEntity { }
        Mock Add-CIPPScheduledTask { }
        Mock Write-LogMessage { }
    }

    Context 'Get-CIPPJITAdminCloudError' {
        It 'returns nothing for Commercial, AllTenants, the partner tenant, an empty filter and an unresolved cloud' {
            Mock Get-CIPPCloudFeatureSupport { }
            Get-CIPPJITAdminCloudError -TenantFilter 'contoso.com' | Should -BeNullOrEmpty
            foreach ($Filter in 'AllTenants', 'PartnerTenant', '', $null) {
                Get-CIPPJITAdminCloudError -TenantFilter $Filter | Should -BeNullOrEmpty
            }
            Mock Get-CIPPTenantRequestCloud { throw 'Unknown cloud environment' }
            Get-CIPPJITAdminCloudError -TenantFilter 'x.onmicrosoft.com' | Should -BeNullOrEmpty
            Should -Invoke Get-CIPPCloudFeatureSupport -Times 0 -Exactly
        }

        It 'refuses GCC High and DoD tenants of a commercial partner with the matrix reason' {
            foreach ($Tenant in 'gov.us', 'dod.mil') {
                $Message = Get-CIPPJITAdminCloudError -TenantFilter $Tenant
                $Message | Should -BeLike "JIT Admin is not supported for $($script:Clouds[$Tenant]) tenants. *cippUser schema extension*"
            }
        }

        It 'still refuses when the matrix cannot be read' {
            Mock Get-CIPPCloudFeatureSupport { throw 'broken' }
            Get-CIPPJITAdminCloudError -TenantFilter 'gov.us' | Should -BeLike 'JIT Admin is not supported for USGovHigh tenants.*'
        }

        It "does not refuse a government tenant in the partner's own cloud" {
            $env:CIPP_PARTNER_CLOUD = 'USGovHigh'
            Get-CIPPJITAdminCloudError -TenantFilter 'gov.us' | Should -BeNullOrEmpty
            Get-CIPPJITAdminCloudError -TenantFilter 'dod.mil' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'ListJITAdmin' {
        It 'refuses a government tenant without reading the schema extension' {
            $Response = Invoke-ListJITAdmin -Request ([pscustomobject]@{ Query = @{ TenantFilter = 'gov.us' }; Headers = @{} }) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 400
            $Response.Body.Results[0] | Should -BeLike '*not supported for USGovHigh*'
            Should -Invoke Get-CIPPSchemaExtensions -Times 0 -Exactly
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
        }

        It 'lists a commercial tenant as before' {
            # the endpoint clears and reuses its request list, so record the first URL when it is sent
            $script:FirstUrl = $null
            Mock New-GraphBulkRequest { if (-not $script:FirstUrl) { $script:FirstUrl = $Requests[0].url } }
            $Response = Invoke-ListJITAdmin -Request ([pscustomobject]@{ Query = @{ TenantFilter = 'contoso.com' }; Headers = @{} }) -TriggerMetadata $null
            $Response.StatusCode | Should -Be 200
            Should -Invoke Get-CIPPSchemaExtensions -Times 1 -Exactly
            Should -Invoke New-GraphBulkRequest -ParameterFilter { $tenantid -eq 'contoso.com' }
            $script:FirstUrl | Should -BeLike '*extabc_cippUser/jitAdminEnabled*'
        }

        It 'skips a government tenant in the AllTenants fan-out and lists a commercial one' {
            Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = $TenantFilter } }
            Push-ExecJITAdminListAllTenants -Item ([pscustomobject]@{ customerId = 'gov.us' })
            Should -Invoke Get-CIPPSchemaExtensions -Times 0 -Exactly
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly

            Push-ExecJITAdminListAllTenants -Item ([pscustomobject]@{ customerId = 'contoso.com' })
            Should -Invoke Get-CIPPSchemaExtensions -Times 1 -Exactly
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'contoso.com' }
        }
    }

    Context 'ExecJITAdmin and Set-CIPPUserJITAdmin' {
        It 'refuses to create or elevate a JIT admin in a government tenant' {
            Mock Set-CIPPUserJITAdminProperties { }
            $Response = Invoke-ExecJITAdmin -Request (New-ExecRequest -Tenant 'gov.us') -TriggerMetadata $null
            $Response.StatusCode | Should -Be 400
            $Response.Body.Results[0] | Should -BeLike '*not supported for USGovHigh*'
            Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
            Should -Invoke Set-CIPPUserJITAdminProperties -Times 0 -Exactly

            foreach ($Action in 'Create', 'AddRoles', 'AddGroups', 'AddRolesAndGroups') {
                { Set-CIPPUserJITAdmin -TenantFilter 'dod.mil' -User @{ UserPrincipalName = 'jit@dod.mil' } -Action $Action -WhatIf } | Should -Throw '*not supported for USGovDoD*'
            }
            Should -Invoke Get-CIPPSchemaExtensions -Times 0 -Exactly
        }

        It 'schedules a commercial JIT admin as before' {
            $Response = Invoke-ExecJITAdmin -Request (New-ExecRequest -Tenant 'contoso.com') -TriggerMetadata $null
            $Response.StatusCode | Should -Be 200
            Should -Invoke Add-CIPPScheduledTask -Times 2 -Exactly
            { Set-CIPPUserJITAdmin -TenantFilter 'contoso.com' -User @{ UserPrincipalName = 'jit@contoso.com' } -Action 'AddRoles' -WhatIf } | Should -Not -Throw
        }

        It 'refuses an approved government request without claiming it, and provisions an approved commercial one' {
            Mock Update-AzDataTableEntity { }
            Mock Get-CIPPAzDataTableEntity { }
            foreach ($Tenant in 'gov.us', 'contoso.com') {
                $Body = (New-ExecRequest -Tenant $Tenant).Body
                $script:Row = [pscustomobject]@{
                    PartitionKey = 'JITAdminRequest'; RowKey = '11111111-1111-1111-1111-111111111111'; ETag = 'e'
                    State = 'Approved'; RequestedBy = 'admin@contoso.com'; Tenant = $Tenant
                    RequestBody = ($Body | ConvertTo-Json -Depth 10 -Compress)
                }
                Mock Get-CIPPAzDataTableEntity { $script:Row } -ParameterFilter { $Filter -like "*JITAdminRequest*" }
                $Request = New-ExecRequest -Tenant $Tenant
                $Request.Body = [pscustomobject]@{ ApprovalRequestId = $script:Row.RowKey }
                $script:Response = Invoke-ExecJITAdmin -Request $Request -TriggerMetadata $null
                if ($Tenant -eq 'gov.us') {
                    $script:Response.StatusCode | Should -Be 400
                    $script:Response.Body.Results[0] | Should -BeLike '*not supported for USGovHigh*'
                    Should -Invoke Update-AzDataTableEntity -Times 0 -Exactly
                    Should -Invoke Add-CIPPScheduledTask -Times 0 -Exactly
                }
            }
            $script:Response.StatusCode | Should -Be 200
            Should -Invoke Update-AzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.State -eq 'Completed' }
            Should -Invoke Add-CIPPScheduledTask -Times 2 -Exactly
            # the commercial request is checked once, before the claim, exactly as an unapproved request is
            Should -Invoke Get-CIPPTenantRequestCloud -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.com' }
        }

        It 'lets removals run for a government tenant' {
            foreach ($Action in 'RemoveRoles', 'RemoveGroups', 'RemoveRolesAndGroups', 'DeleteUser', 'DisableUser') {
                { Set-CIPPUserJITAdmin -TenantFilter 'gov.us' -User @{ UserPrincipalName = 'jit@gov.us' } -Action $Action -WhatIf } | Should -Not -Throw
            }
        }
    }

    Context 'Set-CIPPUserJITAdminProperties' {
        It 'writes nothing for a government tenant' {
            Set-CIPPUserJITAdminProperties -TenantFilter 'gov.us' -UserId 'u1' -Clear
            Should -Invoke Get-CIPPSchemaExtensions -Times 0 -Exactly
            Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        }

        It 'writes the extension for a commercial tenant as before' {
            Set-CIPPUserJITAdminProperties -TenantFilter 'contoso.com' -UserId 'u1' -Clear
            Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'contoso.com' -and $Body -match 'extabc_cippUser' }
        }
    }

    Context 'MFAAdmins alert' {
        BeforeEach {
            Mock New-GraphGetRequest { @() } -ParameterFilter { $uri -like '*conditionalAccess*' }
            Mock New-GraphGetRequest { @([pscustomobject]@{ id = 'jit1' }) } -ParameterFilter { $uri -like '*jitAdminEnabled*' }
            Mock Get-CIPPMFAStateReport {
                @(
                    [pscustomobject]@{ ID = 'a1'; UPN = 'a1@x'; DisplayName = 'Admin'; IsAdmin = $true; MFARegistration = $false; UserType = 'Member'; AccountEnabled = $true }
                    [pscustomobject]@{ ID = 'jit1'; UPN = 'jit1@x'; DisplayName = 'JIT'; IsAdmin = $true; MFARegistration = $false; UserType = 'Member'; AccountEnabled = $true }
                )
            }
            Mock Write-AlertTrace { }
        }

        It 'alerts on every admin in a government tenant without the JIT extension filter' {
            Get-CIPPAlertMFAAdmins -TenantFilter 'gov.us' -InputValue $false
            Should -Invoke Get-CIPPSchemaExtensions -Times 0 -Exactly
            Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*jitAdminEnabled*' }
            Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter { @($data).Count -eq 2 }
        }

        It 'filters out JIT admins in a commercial tenant as before' {
            Get-CIPPAlertMFAAdmins -TenantFilter 'contoso.com' -InputValue $false
            Should -Invoke Get-CIPPSchemaExtensions -Times 1 -Exactly
            Should -Invoke Write-AlertTrace -Times 1 -Exactly -ParameterFilter { @($data).Count -eq 1 -and $data[0].Id -eq 'a1' }
        }
    }
}

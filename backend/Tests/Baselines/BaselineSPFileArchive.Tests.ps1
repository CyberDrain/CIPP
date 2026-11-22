# SPFileArchive is a declarative definition with no hook or executor of its own: the engine reads the SPOTenant
# cache and hands the rendered properties to the generic SPOTenant executor. These tests run the REAL definition
# through the REAL engine against a mocked SPOTenant cache row and pin the grading verdicts and the write shape,
# including that a switch saved as false is not replaced by its default of true.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Set-CippBaselineRunContext { param($RunId) }
    function Update-CippQueueEntry { param($RowKey, $Status, $Name) }
    function Get-CippTable { param($tablename) @{} }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail, $RunId, $Remediated) }
    function Set-CIPPBaselineResult { param($Result, $Prior, $RunId) }
    function Send-CIPPBaselineAlert { param($Result) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Wait-CIPPBaselineCacheReady { param($TenantFilter, $Definition, $RunId) $false }
    function Set-CIPPDBCacheSPOTenant { param($TenantFilter) }
    function Invoke-CIPPBaselineSPOTenant { param($Remediate, $TenantFilter, $Current) }
    function Get-CIPPSPOTenant { param($TenantFilter) }
    function Set-CIPPSPOTenant { [CmdletBinding()] param([Parameter(ValueFromPipeline = $true)]$InputObject, $Properties, $MethodName, $MethodParameters, [switch]$UseCertificate) process { } }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Expand-CIPPBaselineToken.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Invoke-CIPPBaselineStandard.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/SharePoint Standards/SPFileArchive.json') -Raw | ConvertFrom-Json

    function New-EngineItem {
        param($Variables)
        @{
            TenantFilter = $script:Tenant; Standard = 'SPFileArchive'; BaseName = 'SPFileArchive'
            Variables = $Variables; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true
        }
    }
    # Get-CIPPSPOTenant output round-trips through the CIPPDb as JSON; the archive switches are Booleans there.
    function New-CachedTenant {
        param([bool]$AllowFileArchive, [bool]$OnNewSites)
        [PSCustomObject]@{
            EnableSiteArchive                   = $true
            AllowFileArchive                    = $AllowFileArchive
            AllowFileArchiveOnNewSitesByDefault = $OnNewSites
            ArchivedFileStorageUsageMB          = 2048
            StorageQuota                        = 1191936
        } | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    }
}

Describe 'SPFileArchive definition' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Set-CIPPBaselineResult { }
        Mock Add-CIPPBaselineHistoryEvent { }
        Mock Send-CIPPBaselineAlert { }
        Mock Write-LogMessage { }
        Mock Invoke-CIPPBaselineSPOTenant { }
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ SHAREPOINTSTANDARD = $true } }
    }

    Context 'grading' {
        It 'is compliant when both switches already match' {
            Mock New-CIPPDbRequest { New-CachedTenant -AllowFileArchive $true -OnNewSites $true }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ state = $true; newSites = $true })) -Mode 'compare'
            $Result.Compliant | Should -BeTrue
            $Result.ExpectedValue.AllowFileArchive | Should -BeOfType [bool]
        }

        It 'grades file archiving turned off as drift on that switch only' {
            Mock New-CIPPDbRequest { New-CachedTenant -AllowFileArchive $false -OnNewSites $true }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ state = $true; newSites = $true })) -Mode 'compare'
            $Result.Compliant | Should -BeFalse
            @($Result.Diff).Property | Should -Contain 'AllowFileArchive'
            @($Result.Diff).Property | Should -Not -Contain 'AllowFileArchiveOnNewSitesByDefault'
        }

        It 'grades file archiving on new sites turned off as drift on that switch only' {
            Mock New-CIPPDbRequest { New-CachedTenant -AllowFileArchive $true -OnNewSites $false }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ state = $true; newSites = $true })) -Mode 'compare'
            $Result.Compliant | Should -BeFalse
            $Result.Outcome | Should -Be 'Drift'
            @($Result.Diff).Property | Should -Be @('AllowFileArchiveOnNewSitesByDefault')
        }

        It 'grades file archiving on new sites turned on as drift when the baseline turns it off' {
            Mock New-CIPPDbRequest { New-CachedTenant -AllowFileArchive $true -OnNewSites $true }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ state = $true; newSites = $false })) -Mode 'compare'
            $Result.Compliant | Should -BeFalse
            $Result.Outcome | Should -Be 'Drift'
            @($Result.Diff).Property | Should -Be @('AllowFileArchiveOnNewSitesByDefault')
        }

        It 'keeps an explicit false: compliant when the tenant has it off, drift when it is on' {
            Mock New-CIPPDbRequest { New-CachedTenant -AllowFileArchive $false -OnNewSites $false }
            $Off = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ state = $false; newSites = $false })) -Mode 'compare'
            $Off.Compliant | Should -BeTrue
            $Off.ExpectedValue.AllowFileArchive | Should -BeExactly $false
            $Off.ExpectedValue.AllowFileArchiveOnNewSitesByDefault | Should -BeExactly $false

            Mock New-CIPPDbRequest { New-CachedTenant -AllowFileArchive $true -OnNewSites $false }
            $On = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ state = $false; newSites = $false })) -Mode 'compare'
            $On.Compliant | Should -BeFalse
            @($On.Diff).Property | Should -Be @('AllowFileArchive')
        }

        It 'applies the default of on for switches that were never saved' {
            Mock New-CIPPDbRequest { New-CachedTenant -AllowFileArchive $true -OnNewSites $true }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{})) -Mode 'compare'
            $Result.ExpectedValue.AllowFileArchive | Should -BeExactly $true
            $Result.ExpectedValue.AllowFileArchiveOnNewSitesByDefault | Should -BeExactly $true
            $Result.Compliant | Should -BeTrue
        }

        It 'reports No Data rather than drift when the SPOTenant cache is empty' {
            Mock New-CIPPDbRequest { @() }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ state = $true; newSites = $true })) -Mode 'compare'
            $Result.Compliant | Should -BeFalse
            $Result.Outcome | Should -BeExactly 'Skipped-NoCache'
            $Result.Status | Should -BeExactly 'No Data'
            Should -Invoke Invoke-CIPPBaselineSPOTenant -Times 0 -Exactly
        }
    }

    Context 'remediation' {
        It 'writes <Name> to the SPOTenant executor as Booleans' -ForEach @(
            @{ Name = 'file archiving off, new sites on'; State = $false; NewSites = $true }
            @{ Name = 'file archiving on, new sites off'; State = $true; NewSites = $false }
            @{ Name = 'new sites off when only that switch differs'; State = $true; NewSites = $false; OnlyNewSites = $true }
            @{ Name = 'new sites on when only that switch differs'; State = $false; NewSites = $true; OnlyNewSites = $true }
        ) {
            $WantState = $State
            $WantNewSites = $NewSites
            $CachedState = if ($OnlyNewSites) { $State } else { -not $State }
            Mock New-CIPPDbRequest { New-CachedTenant -AllowFileArchive $CachedState -OnNewSites (-not $WantNewSites) }

            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ state = $State; newSites = $NewSites })) -Mode 'oneoff'

            $Result.Remediated | Should -BeTrue
            Should -Invoke Invoke-CIPPBaselineSPOTenant -Times 1 -Exactly -ParameterFilter {
                $TenantFilter -eq $script:Tenant -and
                @($Remediate.properties.PSObject.Properties.Name).Count -eq 2 -and
                $Remediate.properties.AllowFileArchive -is [bool] -and $Remediate.properties.AllowFileArchive -eq $WantState -and
                $Remediate.properties.AllowFileArchiveOnNewSitesByDefault -is [bool] -and $Remediate.properties.AllowFileArchiveOnNewSitesByDefault -eq $WantNewSites
            }
        }

        It 'does not write when the tenant already complies' {
            Mock New-CIPPDbRequest { New-CachedTenant -AllowFileArchive $true -OnNewSites $true }
            $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ state = $true; newSites = $true })) -Mode 'run'
            Should -Invoke Invoke-CIPPBaselineSPOTenant -Times 0 -Exactly
        }
    }
}

Describe 'SPFileArchive through the SPOTenant executor' {
    BeforeAll {
        . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Executors/Invoke-CIPPBaselineSPOTenant.ps1')
    }

    It 'sends <Name> to Set-CIPPSPOTenant as Booleans' -ForEach @(
        @{ Name = 'file archiving off'; Spec = '{"executor":"SPOTenant","properties":{"AllowFileArchive":false,"AllowFileArchiveOnNewSitesByDefault":true}}'; State = $false; NewSites = $true }
        @{ Name = 'new sites off'; Spec = '{"executor":"SPOTenant","properties":{"AllowFileArchive":true,"AllowFileArchiveOnNewSitesByDefault":false}}'; State = $true; NewSites = $false }
    ) {
        $WantState = $State
        $WantNewSites = $NewSites
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ _ObjectIdentity_ = 'id'; TenantFilter = $script:Tenant } }
        Mock Set-CIPPSPOTenant { }

        Invoke-CIPPBaselineSPOTenant -Remediate ($Spec | ConvertFrom-Json) -TenantFilter $script:Tenant -Current $null

        Should -Invoke Set-CIPPSPOTenant -Times 1 -Exactly -ParameterFilter {
            $Properties.Count -eq 2 -and
            $Properties['AllowFileArchive'] -is [bool] -and $Properties['AllowFileArchive'] -eq $WantState -and
            $Properties['AllowFileArchiveOnNewSitesByDefault'] -is [bool] -and $Properties['AllowFileArchiveOnNewSitesByDefault'] -eq $WantNewSites
        }
    }
}

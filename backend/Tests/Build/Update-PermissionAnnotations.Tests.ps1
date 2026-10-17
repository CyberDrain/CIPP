# Pester tests for build/tools/Update-PermissionAnnotations.ps1
# Runs the script over a fixture module tree with a small permissions map and Learn table, so the cases do
# not move when Microsoft's data changes.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:ScriptPath = Join-Path (Split-Path -Parent $RepoRoot) 'build/tools/Update-PermissionAnnotations.ps1'

    $script:Modules = Join-Path $TestDrive 'Modules'
    $HttpDir = Join-Path $Modules 'CIPPHTTP/Public/Entrypoints/HTTP Functions'
    $CoreDir = Join-Path $Modules 'CIPPCore/Public'
    $null = New-Item -ItemType Directory -Path $HttpDir, $CoreDir -Force

    Set-Content -Path (Join-Path $HttpDir 'Invoke-ExecFixtureUser.ps1') -Value @'
function Invoke-ExecFixtureUser {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    param($Request)
    $User = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Request.Body.id)" -tenantid $TenantFilter
    Set-FixtureUser -Id $User.id
}
'@
    Set-Content -Path (Join-Path $CoreDir 'Set-FixtureUser.ps1') -Value @'
function Set-FixtureUser {
    # A leading comment that must not become help.
    param($Id)
    New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/users/$Id" -type PATCH -tenantid $TenantFilter -body '{}'
}
'@
    Set-Content -Path (Join-Path $HttpDir 'Invoke-ListFixtureGroups.ps1') -Value @'
function Invoke-ListFixtureGroups {
    <#
    .FUNCTIONALITY
        Entrypoint
    .NOTES
        Groups are read app-only.
        Permission: Exchange | Get-Mailbox | Delegated | View-Only Recipients
        Permission: Graph | GET /custom | Delegated | Custom.Read.All
    #>
    param($Request)
    $BaseUri = 'https://graph.microsoft.com/beta/groups'
    New-GraphGetRequest -uri "$BaseUri/$($Request.Query.id)/members" -tenantid $TenantFilter -AsApp $true
    New-GraphGetRequest -uri $Request.Query.Uri -tenantid $TenantFilter
}
'@
    Set-Content -Path (Join-Path $HttpDir 'Invoke-ExecFixtureDevices.ps1') -Value @'
function Invoke-ExecFixtureDevices {

    # Help may follow a line comment set apart by a blank line.

    <#
    .FUNCTIONALITY
        Entrypoint
    .NOTES
        Permission: Graph | GET /old | Delegated | Old.Read.All
        Permission: Graph | GET /users/{id}/managedDevices | Delegated | Wrong.Read | | only for Intune tenants
    #>
    param($Request)
    if ($Request.Body.Intune) { $Root = 'deviceManagement' } else { $Root = 'notAResource' }
    New-GraphGetRequest -uri "https://graph.microsoft.com/beta/$Root/managedDevices" -tenantid $TenantFilter
    New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Request.Body.id)/managedDevices" -tenantid $TenantFilter
    New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/groups/$($Request.Body.id)/members/`$ref" -type POST -tenantid $TenantFilter -body '{}'
}
'@
    Set-Content -Path (Join-Path $CoreDir 'Get-FixtureUndocumented.ps1') -Value @'
<#
.SYNOPSIS
    Help before the function keyword.
#>
function Get-FixtureUndocumented {
    param()
    New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/undocumentedPolicy' -tenantid $TenantFilter
}
'@

    $script:Metadata = Join-Path $TestDrive 'graph-metadata'
    $null = New-Item -ItemType Directory -Path $Metadata -Force
    $Csdl = @'
<?xml version="1.0" encoding="utf-8"?>
<edmx:Edmx Version="4.0" xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx"><edmx:DataServices>
<Schema Namespace="microsoft.graph" Alias="graph" xmlns="http://docs.oasis-open.org/odata/ns/edm">
<EntityType Name="entity"><Key><PropertyRef Name="id" /></Key><Property Name="id" Type="Edm.String" /></EntityType>
<EntityType Name="directoryObject" BaseType="graph.entity" />
<EntityType Name="user" BaseType="graph.directoryObject"><NavigationProperty Name="managedDevices" Type="Collection(graph.managedDevice)" ContainsTarget="true" /></EntityType>
<EntityType Name="group" BaseType="graph.directoryObject"><NavigationProperty Name="members" Type="Collection(graph.directoryObject)" /></EntityType>
<EntityType Name="managedDevice" BaseType="graph.entity" />
<EntityType Name="deviceManagement" BaseType="graph.entity"><NavigationProperty Name="managedDevices" Type="Collection(graph.managedDevice)" ContainsTarget="true" /></EntityType>
<EntityContainer Name="GraphService"><EntitySet Name="users" EntityType="microsoft.graph.user" /><EntitySet Name="groups" EntityType="microsoft.graph.group" /><Singleton Name="deviceManagement" Type="microsoft.graph.deviceManagement" /></EntityContainer>
</Schema></edmx:DataServices></edmx:Edmx>
'@
    Set-Content -Path (Join-Path $Metadata 'v1.0.xml'), (Join-Path $Metadata 'beta.xml') -Value $Csdl

    $script:PermissionsPath = Join-Path $TestDrive 'permissions.json'
    Set-Content -Path $PermissionsPath -Value (@{
            permissions = @{
                'User.ReadBasic.All'                      = @{ schemes = @{ DelegatedWork = @{ privilegeLevel = 2 } }; pathSets = @(@{ schemeKeys = @('DelegatedWork'); methods = @('GET'); paths = @{ '/users/{id}' = 'least=DelegatedWork' } }) }
                'User.Read.All'                           = @{ schemes = @{ DelegatedWork = @{ privilegeLevel = 3 } }; pathSets = @(@{ schemeKeys = @('DelegatedWork'); methods = @('GET'); paths = @{ '/users/{id}' = '' } }) }
                'User.ReadWrite.All'                      = @{ schemes = @{ DelegatedWork = @{ privilegeLevel = 4 } }; pathSets = @(@{ schemeKeys = @('DelegatedWork'); methods = @('GET', 'PATCH'); paths = @{ '/users/{id}' = 'least=DelegatedWork' } }) }
                'DeviceManagementApps.Read.All'           = @{ schemes = @{ DelegatedWork = @{ privilegeLevel = 3 } }; pathSets = @(@{ schemeKeys = @('DelegatedWork'); methods = @('PATCH'); paths = @{ '/users/{id}' = '' } }) }
                'GroupMember.Read.All'                    = @{ schemes = @{ Application = @{ privilegeLevel = 3 } }; pathSets = @(@{ schemeKeys = @('Application'); methods = @('GET'); paths = @{ '/groups/{id}/members' = 'least=Application' } }) }
                'Group-NestingSupport.ReadWrite.All'      = @{ schemes = @{ Application = @{ privilegeLevel = 2 } }; pathSets = @(@{ schemeKeys = @('Application'); methods = @('GET'); paths = @{ '/groups/{id}/members' = 'least=Application' } }) }
                'GroupMember.ReadWrite.All'               = @{ schemes = @{ DelegatedWork = @{ privilegeLevel = 3 } }; pathSets = @(@{ schemeKeys = @('DelegatedWork'); methods = @('DELETE'); paths = @{ '/groups/{id}/members/{id}' = 'least=DelegatedWork' } }) }
                'DeviceManagementManagedDevices.Read.All' = @{ schemes = @{ DelegatedWork = @{ privilegeLevel = 3 } }; pathSets = @(@{ schemeKeys = @('DelegatedWork'); methods = @('GET'); paths = @{ '/devicemanagement/manageddevices' = 'least=DelegatedWork' } }) }
            }
        } | ConvertTo-Json -Depth 10)
    # Learn lists User.Read first because the page also covers GET /me.
    $script:LearnPath = Join-Path $TestDrive 'learn.json'
    Set-Content -Path $LearnPath -Value (@{
            tables = @(
                @{ DelegatedWork = @{ least = @('User.Read'); higher = @('User.ReadWrite', 'User.ReadBasic.All', 'User.Read.All', 'User.ReadWrite.All', 'Directory.Read.All') } }
                @{ Application = @{ least = @('GroupMember.Read.All'); higher = @('Group.Read.All', 'Directory.Read.All') } }
            )
            'v1.0' = @{ 'GET /users/{id}' = 0 }
            beta   = @{ 'GET /groups/{id}/members' = 1 }
        } | ConvertTo-Json -Depth 10)
    Set-Content -Path (Join-Path $TestDrive 'translator.json') -Value '[{ "id": "rw", "value": "User.ReadWrite.All" }]'
    Set-Content -Path (Join-Path $TestDrive 'sam.json') -Value '{ "requiredResourceAccess": [{ "resourceAppId": "00000003-0000-0000-c000-000000000000", "resourceAccess": [{ "id": "rw", "type": "Scope" }] }] }'

    $script:Arguments = @{
        ModulesPath       = $Modules
        PermissionsPath   = $PermissionsPath
        LearnPath         = $LearnPath
        SamManifestPath   = Join-Path $TestDrive 'sam.json'
        TranslatorPath    = Join-Path $TestDrive 'translator.json'
        GraphMetadataPath = $Metadata
    }
    $script:ReportPath = Join-Path $TestDrive 'report.json'
    $null = & $ScriptPath @Arguments -ReportPath $ReportPath 6>$null
    $script:Report = Get-Content $ReportPath -Raw | ConvertFrom-Json

    function Get-Function([string]$File, [string]$Name) {
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File, [ref]$null, [ref]$null)
        $Ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $Name }, $true)[0]
    }
    function Get-Line([string]$File, [string]$Name) {
        @(((Get-Function $File $Name).GetHelpContent().Notes -split '\r?\n').Where({ $_ -match '^\s*Permission:' }).ForEach({ $_.Trim() }))
    }
    $script:UserFile = Join-Path $HttpDir 'Invoke-ExecFixtureUser.ps1'
    $script:HelperFile = Join-Path $CoreDir 'Set-FixtureUser.ps1'
    $script:GroupsFile = Join-Path $HttpDir 'Invoke-ListFixtureGroups.ps1'
    $script:DevicesFile = Join-Path $HttpDir 'Invoke-ExecFixtureDevices.ps1'
    $script:UndocumentedFile = Join-Path $CoreDir 'Get-FixtureUndocumented.ps1'
}

Describe 'Update-PermissionAnnotations' {
    It 'adds a .NOTES section to existing help and keeps the rest of it' {
        Get-Line $UserFile 'Invoke-ExecFixtureUser' | Should -Be @('Permission: Graph | GET /users/{id} | Delegated | User.ReadBasic.All | User.ReadWrite, User.Read.All, User.ReadWrite.All, Directory.Read.All')
        $Help = (Get-Function $UserFile 'Invoke-ExecFixtureUser').GetHelpContent()
        $Help.Role.Trim() | Should -Be 'Identity.User.ReadWrite'
        $Help.Functionality.Trim() | Should -Be 'Entrypoint'
    }

    It 'gives a function without help a new block with only its own calls' {
        Get-Line $HelperFile 'Set-FixtureUser' | Should -Be @('Permission: Graph | PATCH /users/{id} | Delegated | User.ReadWrite.All')
    }

    It 'falls back to the map for higher when Learn has no page, keeping only related permissions' {
        (Get-Content $HelperFile -Raw) | Should -Not -Match 'DeviceManagementApps'
    }

    It 'marks -AsApp calls Application and takes higher from Learn' {
        (Get-Line $GroupsFile 'Invoke-ListFixtureGroups')[0] | Should -Be 'Permission: Graph | GET /groups/{id}/members | Application | GroupMember.Read.All | Group.Read.All, Directory.Read.All'
    }

    It 'keeps hand-written lines and other notes where a call cannot be read' {
        Get-Line $GroupsFile 'Invoke-ListFixtureGroups' | Should -Contain 'Permission: Exchange | Get-Mailbox | Delegated | View-Only Recipients'
        Get-Line $GroupsFile 'Invoke-ListFixtureGroups' | Should -Contain 'Permission: Graph | GET /custom | Delegated | Custom.Read.All'
        (Get-Function $GroupsFile 'Invoke-ListFixtureGroups').GetHelpContent().Notes | Should -Match 'Groups are read app-only\.'
        $Report.Where({ $_.function -eq 'Invoke-ListFixtureGroups' })[0].graphGaps | Should -BeLike 'unreadable URI: *Query.Uri*'
    }

    It 'drops a stale line, refreshes a derivable one and keeps its condition' {
        $Lines = Get-Line $DevicesFile 'Invoke-ExecFixtureDevices'
        $Lines | Should -Not -Contain 'Permission: Graph | GET /old | Delegated | Old.Read.All'
        $Lines | Should -Contain 'Permission: Graph | GET /users/{id}/managedDevices | Delegated | DeviceManagementManagedDevices.Read.All | | only for Intune tenants'
    }

    It 'keeps only the branch combinations the schema has and rematches by $ref pair' {
        $Lines = Get-Line $DevicesFile 'Invoke-ExecFixtureDevices'
        $Lines | Should -Contain 'Permission: Graph | GET /deviceManagement/managedDevices | Delegated | DeviceManagementManagedDevices.Read.All'
        $Lines | Should -Contain 'Permission: Graph | POST /groups/{id}/members/$ref | Delegated | GroupMember.ReadWrite.All'
        ($Lines -join "`n") | Should -Not -Match 'notAResource'
    }

    It 'reports calls outside the schema instead of annotating them' {
        Get-Line $UndocumentedFile 'Get-FixtureUndocumented' | Should -BeNullOrEmpty
        $Report.Where({ $_.function -eq 'Get-FixtureUndocumented' })[0].graphGaps | Should -Be @('GET /policies/undocumentedPolicy (not in the Graph beta schema)')
    }

    It 'is idempotent and passes -Check' {
        $Before = Get-Content $DevicesFile -Raw
        $null = & $ScriptPath @Arguments 6>$null
        Get-Content $DevicesFile -Raw | Should -BeExactly $Before
        { & $ScriptPath @Arguments -Check 6>$null } | Should -Not -Throw
    }

    It '-Check fails when a line is missing' {
        $Text = Get-Content $HelperFile -Raw
        Set-Content -Path $HelperFile -Value ($Text -replace '(?m)^\s*Permission:.*\r?\n', '') -NoNewline
        { & $ScriptPath @Arguments -Check 6>$null } | Should -Throw -ExpectedMessage '*stale Permission lines*'
        Set-Content -Path $HelperFile -Value $Text -NoNewline
    }
}

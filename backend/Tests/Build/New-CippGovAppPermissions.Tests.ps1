# Pester tests for build/tools/New-CippGovAppPermissions.ps1 (redanthrax/CIPP#4). The Azure Government app needs
# CIPP-SAM's Microsoft Graph permissions, matched by name because Graph in Azure Government uses different ids for
# some of them and lacks others. The fixture is the GCC High Graph service principal's permission ids and names.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $RepoRoot = Split-Path -Parent $BackendRoot
    $script:Tool = Join-Path $RepoRoot 'build/tools/New-CippGovAppPermissions.ps1'
    $script:Fixture = Join-Path $BackendRoot 'Tests/Fixtures/GovCloud/GraphServicePrincipal.USGovHigh.json'
    $script:Manifest = [System.IO.File]::ReadAllText((Join-Path $BackendRoot 'Config/SAMManifest.json')) | ConvertFrom-Json
    $script:Gov = [System.IO.File]::ReadAllText($script:Fixture) | ConvertFrom-Json
    $script:GraphManifest = @(($script:Manifest.requiredResourceAccess | Where-Object resourceAppId -EQ '00000003-0000-0000-c000-000000000000').resourceAccess)
    $script:Result = & $script:Tool -ServicePrincipalPath $script:Fixture -WarningVariable script:Warnings -WarningAction SilentlyContinue
}

Describe 'New-CippGovAppPermissions' {
    It 'returns a Microsoft Graph requiredResourceAccess entry' {
        $script:Result.resourceAppId | Should -Be '00000003-0000-0000-c000-000000000000'
        @($script:Result.resourceAccess).Count | Should -BeGreaterThan 100
    }

    It 'uses only ids that exist in Azure Government Graph, with the matching type' {
        $Scopes = @($script:Gov.oauth2PermissionScopes.id)
        $Roles = @($script:Gov.appRoles.id)
        foreach ($Access in $script:Result.resourceAccess) {
            if ($Access.type -eq 'Role') { $Access.id | Should -BeIn $Roles } else { $Access.type | Should -Be 'Scope'; $Access.id | Should -BeIn $Scopes }
        }
    }

    It 'accounts for every manifest permission as either granted or missing' {
        (@($script:Result.resourceAccess).Count + @($script:Result.Missing).Count) | Should -Be $script:GraphManifest.Count
    }

    It 'translates a permission whose id differs in Azure Government' {
        $Changed = @($script:Result.resourceAccess | Where-Object { $_.id -notin $script:GraphManifest.id })
        $Changed.Count | Should -BeGreaterThan 0 -Because 'some Graph permission ids differ in GCC High'
    }

    It 'reports the permissions GCC High Graph does not have and warns about each' {
        $Known = @(
            'RoleManagement.ReadWrite.Exchange|application'
            'TeamsUserConfiguration.Read.All|application'
            'ThreatSubmission.ReadWrite.All|application'
            'DelegatedAdminRelationship.ReadWrite.All|delegated'
            'TeamsUserConfiguration.Read.All|delegated'
            'RoleManagement.Read.Exchange|delegated'
        )
        $Missing = @($script:Result.Missing | ForEach-Object { '{0}|{1}' -f $_.Name, $_.Type })
        foreach ($Item in $Missing) { $Item | Should -BeIn $Known -Because 'this permission exists in the GCC High fixture' }
        @($script:Warnings).Count | Should -Be $Missing.Count
    }

    It 'writes the entry as JSON with -OutFile' {
        $Out = Join-Path $TestDrive 'gov.json'
        $null = & $script:Tool -ServicePrincipalPath $script:Fixture -OutFile $Out -WarningAction SilentlyContinue
        $Written = [System.IO.File]::ReadAllText($Out) | ConvertFrom-Json
        $Written.resourceAppId | Should -Be '00000003-0000-0000-c000-000000000000'
        @($Written.resourceAccess).Count | Should -Be @($script:Result.resourceAccess).Count
        $Written.PSObject.Properties.Name | Should -Not -Contain 'Missing'
    }

    It 'refuses a file that is not the Microsoft Graph service principal' {
        $Other = Join-Path $TestDrive 'other.json'
        [System.IO.File]::WriteAllText($Other, '{"appId":"00000002-0000-0ff1-ce00-000000000000","appRoles":[{"id":"a","value":"x"}],"oauth2PermissionScopes":[{"id":"b","value":"y"}]}')
        { & $script:Tool -ServicePrincipalPath $Other } | Should -Throw '*not Microsoft Graph*'
        $Empty = Join-Path $TestDrive 'empty.json'
        [System.IO.File]::WriteAllText($Empty, '{"value":[]}')
        { & $script:Tool -ServicePrincipalPath $Empty } | Should -Throw '*appRoles and oauth2PermissionScopes*'
    }
}

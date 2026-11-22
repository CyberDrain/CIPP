# Pester tests for Invoke-ExecSharePointFileArchive

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ExecSharePointFileArchive.ps1'
    if (-not (Test-Path $EndpointPath)) { throw "Could not locate $EndpointPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphPOSTRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp, $type, $body, $AddedHeaders) }
    function Get-Tenants { param($TenantFilter) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }

    . $EndpointPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    function New-TestRequest {
        param([hashtable]$Body)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecSharePointFileArchive' }
            Headers = @{}
            Body    = [pscustomobject]$Body
        }
    }
}

Describe 'Invoke-ExecSharePointFileArchive' {
    BeforeEach {
        Mock New-GraphPOSTRequest { }
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'contoso.com' } }
        Mock Write-LogMessage { }
    }

    It 'returns BadRequest for <Name>' -ForEach @(
        @{ Name = 'a missing tenantFilter'; Body = @{ DriveId = 'b!drive'; ItemId = '01ITEM'; Action = 'Archive' } }
        @{ Name = 'a missing DriveId'; Body = @{ tenantFilter = 'contoso.com'; ItemId = '01ITEM'; Action = 'Archive' } }
        @{ Name = 'a DriveId with a path in it'; Body = @{ tenantFilter = 'contoso.com'; DriveId = 'b!drive/items'; ItemId = '01ITEM'; Action = 'Archive' } }
        @{ Name = 'a missing ItemId'; Body = @{ tenantFilter = 'contoso.com'; DriveId = 'b!drive'; Action = 'Archive' } }
        @{ Name = 'an ItemId with a path in it'; Body = @{ tenantFilter = 'contoso.com'; DriveId = 'b!drive'; ItemId = '01ITEM/permanentDelete'; Action = 'Archive' } }
        @{ Name = 'a missing Action'; Body = @{ tenantFilter = 'contoso.com'; DriveId = 'b!drive'; ItemId = '01ITEM' } }
        @{ Name = 'an unknown Action'; Body = @{ tenantFilter = 'contoso.com'; DriveId = 'b!drive'; ItemId = '01ITEM'; Action = 'Delete' } }
    ) {
        $Response = Invoke-ExecSharePointFileArchive -Request (New-TestRequest -Body $Body)

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'describes a folder as archiving its eligible files, not every file' {
        $Description = (Get-Help Invoke-ExecSharePointFileArchive).description.Text -replace '\s+', ' '
        $Description | Should -BeLike '*the eligible files in a folder*'
        $Description | Should -Not -BeLike '*every file*'
    }

    It 'returns NotFound for a tenant CIPP does not manage' {
        Mock Get-Tenants { }

        $Response = Invoke-ExecSharePointFileArchive -Request (New-TestRequest -Body @{ tenantFilter = 'unknown.example'; DriveId = 'b!drive'; ItemId = '01ITEM'; Action = 'Archive' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
        $Response.Body.Results | Should -BeLike 'CIPP does not manage the tenant*'
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'archives a file' {
        $Response = Invoke-ExecSharePointFileArchive -Request (New-TestRequest -Body @{ tenantFilter = 'contoso.com'; DriveId = 'b!drive'; ItemId = '01ITEM'; ItemName = 'Launch video.mp4'; Action = 'Archive' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -BeLike 'Archived Launch video.mp4*'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -eq 'https://graph.microsoft.com/beta/drives/b!drive/items/01ITEM/archive' -and $tenantid -eq 'contoso.com' -and $AsApp -eq $true -and -not $AddedHeaders
        }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Info' }
    }

    It 'returns Accepted when <Action> a folder, which Microsoft 365 works through in the background' -ForEach @(
        @{ Action = 'Archive'; Operation = 'archive'; Expected = 'Started archiving the eligible files in Video Archive*' }
        @{ Action = 'Reactivate'; Operation = 'unarchive'; Expected = 'Started reactivating the files in Video Archive*' }
    ) {
        $Response = Invoke-ExecSharePointFileArchive -Request (New-TestRequest -Body @{ tenantFilter = 'contoso.com'; DriveId = 'b!drive'; ItemId = '01FOLDER'; ItemName = 'Video Archive'; IsFolder = $true; Action = $Action })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Accepted)
        $Response.Body.Results | Should -BeLike $Expected
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -like "*/items/01FOLDER/$Operation" -and $AddedHeaders.Prefer -eq 'respond-async'
        }
    }

    It 'reports <Expected> when reactivating a file that <Kind>' -ForEach @(
        @{ Kind = 'comes back with no archive status'; GraphResponse = [pscustomobject]@{ file = [pscustomobject]@{ mimeType = 'video/mp4' } }; Expected = 'Reactivated Launch video.mp4*' }
        @{ Kind = 'comes back as notArchived'; GraphResponse = [pscustomobject]@{ file = [pscustomobject]@{ mimeType = 'video/mp4'; archiveStatus = 'notArchived' } }; Expected = 'Reactivated Launch video.mp4*' }
        @{ Kind = 'comes back with no body'; GraphResponse = $null; Expected = 'Reactivated Launch video.mp4*' }
        @{ Kind = 'has to be restored'; GraphResponse = [pscustomobject]@{ file = [pscustomobject]@{ archiveStatus = 'reactivating' } }; Expected = 'Started reactivating Launch video.mp4*' }
    ) {
        $Returned = $GraphResponse
        Mock New-GraphPOSTRequest { $Returned }

        $Response = Invoke-ExecSharePointFileArchive -Request (New-TestRequest -Body @{ tenantFilter = 'contoso.com'; DriveId = 'b!drive'; ItemId = '01ITEM'; ItemName = 'Launch video.mp4'; Action = 'Reactivate' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -BeLike $Expected
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/items/01ITEM/unarchive' }
    }

    It 'returns InternalServerError when Microsoft Graph refuses the request' {
        Mock New-GraphPOSTRequest { throw 'Archive is not enabled for this tenant' }

        $Response = Invoke-ExecSharePointFileArchive -Request (New-TestRequest -Body @{ tenantFilter = 'contoso.com'; DriveId = 'b!drive'; ItemId = '01ITEM'; ItemName = 'Launch video.mp4'; Action = 'Archive' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body.Results | Should -BeLike 'Failed to archive Launch video.mp4: Archive is not enabled*'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' }
    }
}

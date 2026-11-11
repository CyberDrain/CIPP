# The one function that talks to the Managed Baselines service. Mock mode answers from the sample
# files and never calls out; otherwise it sends the key and turns a refusal into a typed error.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-ExtensionAPIKey { param($Extension) }
    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    $script:EnabledConfig = [PSCustomObject]@{ config = '{"CyberDrainManagedBaselines":{"Enabled":true}}' }

    . (Join-Path $script:RepoRoot 'Modules/CippExtensions/Public/ManagedBaselines/Invoke-ManagedBaselinesRequest.ps1')

    function New-HttpError([int]$Status) {
        $Response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
        [Microsoft.PowerShell.Commands.HttpResponseException]::new("Response status code does not indicate success: $Status", $Response)
    }

    $script:SavedRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $script:RepoRoot
}

AfterAll {
    $env:CIPPRootPath = $script:SavedRoot
    $env:CIPP_MANAGED_BASELINES_MOCK = $null
    $env:CIPP_MANAGED_BASELINES_URL = $null
}

Describe 'Invoke-ManagedBaselinesRequest in mock mode' {
    BeforeEach {
        $env:CIPP_MANAGED_BASELINES_MOCK = 'true'
        Mock Invoke-RestMethod {}
        Mock Get-ExtensionAPIKey {}
        Mock Get-CIPPAzDataTableEntity { if ($Context -eq 'Extensionsconfig') { $script:EnabledConfig } }
    }

    It 'refuses to answer while the integration is not enabled' {
        Mock Get-CIPPAzDataTableEntity { [PSCustomObject]@{ config = '{"CyberDrainManagedBaselines":{"Enabled":false}}' } }

        { Invoke-ManagedBaselinesRequest -Path 'account' } | Should -Throw -ExceptionType ([System.ArgumentException]) -ExpectedMessage '*not enabled*'
    }

    It 'answers the account call without a key and without calling out' {
        $Account = Invoke-ManagedBaselinesRequest -Path 'account'

        $Account.mock | Should -BeTrue
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        Should -Invoke Get-ExtensionAPIKey -Times 0 -Exactly
    }

    It 'lists a catalog in which every entry has a package that matches it' {
        $Catalog = @(Invoke-ManagedBaselinesRequest -Path 'templates')

        $Catalog.Count | Should -BeGreaterThan 0
        foreach ($Entry in $Catalog) {
            $Package = Invoke-ManagedBaselinesRequest -Path "templates/$($Entry.id)"
            $Package.id | Should -Be $Entry.id
            $Package.version | Should -Be $Entry.version
            $Package.Baseline.templateName | Should -Be $Entry.name
            @($Package.Baseline.stages.standards).Count | Should -Be $Entry.standardsCount
        }
    }

    It 'only uses standards that exist as definitions' {
        $Definitions = @(Get-ChildItem (Join-Path $script:RepoRoot 'Config/BaselineStandards') -Filter '*.json' -Recurse).BaseName
        $Packages = @(Get-ChildItem (Join-Path $script:RepoRoot 'Config/ManagedBaselineSamples') -Filter '*.json' | Where-Object { $_.Name -ne 'catalog.json' })
        $Packages.Count | Should -BeGreaterThan 1
        foreach ($File in $Packages) {
            $Package = Get-Content $File.FullName -Raw | ConvertFrom-Json -Depth 100
            foreach ($Standard in @($Package.Baseline.stages.standards)) {
                $Definitions | Should -Contain $Standard.standard -Because "$($File.Name) uses it"
            }
        }
    }

    It 'refuses an unknown template as not found' {
        { Invoke-ManagedBaselinesRequest -Path 'templates/does-not-exist' } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
    }

    It 'reports a request as <Expected> when it was sent <Age> seconds ago' -ForEach @(
        @{ Age = 30; Expected = 'submitted'; HasPackage = $false }
        @{ Age = 300; Expected = 'ready'; HasPackage = $true }
    ) {
        $SubmittedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $Age
        Mock Get-CIPPAzDataTableEntity {
            if ($Context -eq 'Extensionsconfig') { $script:EnabledConfig } else { [PSCustomObject]@{ RowKey = 'abc-123'; Status = 'Waiting on CyberDrain'; SubmittedAt = $SubmittedAt } }
        }

        $Answer = Invoke-ManagedBaselinesRequest -Path 'requests/abc-123'

        $Answer.status | Should -Be $Expected
        ($null -ne $Answer.package) | Should -Be $HasPackage
        $Answer.mock | Should -BeTrue
    }

    It 'reports an implemented request as implemented' {
        Mock Get-CIPPAzDataTableEntity {
            if ($Context -eq 'Extensionsconfig') { $script:EnabledConfig } else { [PSCustomObject]@{ RowKey = 'abc-123'; Status = 'Implemented'; SubmittedAt = 1 } }
        }

        (Invoke-ManagedBaselinesRequest -Path 'requests/abc-123').status | Should -Be 'implemented'
    }

    It 'echoes the request id when a request is sent' {
        $Answer = Invoke-ManagedBaselinesRequest -Path 'requests' -Method POST -Body @{ requestId = 'abc-123' }

        $Answer.requestId | Should -Be 'abc-123'
        $Answer.status | Should -Be 'submitted'
    }
}

Describe 'Invoke-ManagedBaselinesRequest against the service' {
    BeforeEach {
        $env:CIPP_MANAGED_BASELINES_MOCK = $null
        $env:CIPP_MANAGED_BASELINES_URL = $null
        Mock Get-ExtensionAPIKey { 'pester-key' }
        Mock Invoke-RestMethod { [PSCustomObject]@{ ok = $true } }
        Mock Get-CIPPAzDataTableEntity { $script:EnabledConfig }
    }

    It 'never calls out while the integration is not enabled' {
        Mock Get-CIPPAzDataTableEntity { }

        { Invoke-ManagedBaselinesRequest -Path 'templates' } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'sends the key and a JSON body to the service' {
        Invoke-ManagedBaselinesRequest -Path '/requests' -Method POST -Body @{ requestId = 'abc-123' } | Out-Null

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            "$Uri" -eq 'https://managedbaselines.cipp.app/api/requests' -and $Method -eq 'POST' -and
            $Headers['x-api-key'] -eq 'pester-key' -and $ContentType -eq 'application/json' -and
            ($Body | ConvertFrom-Json).requestId -eq 'abc-123'
        }
    }

    It 'uses the override address when one is set' {
        $env:CIPP_MANAGED_BASELINES_URL = 'https://staging.example/'

        Invoke-ManagedBaselinesRequest -Path 'templates' | Out-Null

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { "$Uri" -eq 'https://staging.example/api/templates' }
    }

    It 'refuses to call out without a key' {
        Mock Get-ExtensionAPIKey { '' }

        { Invoke-ManagedBaselinesRequest -Path 'account' } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }

    It 'turns status <Status> into <Type>' -ForEach @(
        @{ Status = 401; Type = [System.UnauthorizedAccessException] }
        @{ Status = 402; Type = [System.UnauthorizedAccessException] }
        @{ Status = 403; Type = [System.UnauthorizedAccessException] }
        @{ Status = 404; Type = [System.Management.Automation.ItemNotFoundException] }
    ) {
        Mock Invoke-RestMethod { throw (New-HttpError $Status) }

        { Invoke-ManagedBaselinesRequest -Path 'account' } | Should -Throw -ExceptionType $Type
    }

    It 'says the service could not be reached for any other failure' {
        Mock Invoke-RestMethod { throw (New-HttpError 500) }

        { Invoke-ManagedBaselinesRequest -Path 'account' } | Should -Throw -ExpectedMessage '*could not be reached*'
    }
}

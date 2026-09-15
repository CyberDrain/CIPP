function Invoke-ListAvailableTests {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Dashboard.Read
    .DESCRIPTION
        Lists the compliance tests CIPP can run against a tenant, both the built-in framework tests (CIS, CISA, Essential Eight, EIDSCA, ORCA) and any custom PowerShell tests added to this instance. Returns the catalogue of tests, not their results.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        # Get all test folders
        $TestsRoot = Join-Path $env:CIPPRootPath 'Modules\CIPPTests\Public\Tests'
        $TestFolders = [System.IO.Directory]::EnumerateDirectories($TestsRoot)
        $CustomTestsTable = Get-CippTable -tablename 'CustomPowershellScripts'
        $Filter = "PartitionKey eq 'CustomScript'"
        $AllScripts = Get-CIPPAzDataTableEntity @CustomTestsTable -Filter $Filter
        # Group by ScriptGuid and get latest version of each
        $LatestCustomScripts = $AllScripts |
            Group-Object -Property ScriptGuid |
            ForEach-Object {
                $_.Group | Sort-Object -Property Version -Descending | Select-Object -First 1
            }


        # Built-in tests: the C# engine's registry (tests.registry.json) is the source of truth for
        # every ported test; a few unported tests still live as .ps1 on disk. Merge both, keyed by id
        # (registry wins), then split into Identity/Devices by testType/folder for the UI.
        $ById = [ordered]@{}

        $RegistryPath = Join-Path $env:CIPPRootPath 'Modules\CIPPTests\tests.registry.json'
        if (Test-Path $RegistryPath) {
            $Registry = Get-Content -Path $RegistryPath -Raw | ConvertFrom-Json
            foreach ($Suite in $Registry.suites) {
                foreach ($Test in $Suite.tests) {
                    if ([string]::IsNullOrWhiteSpace($Test.id)) { continue }
                    $ById[$Test.id] = [PSCustomObject]@{
                        id         = $Test.id
                        name       = if ($Test.name) { $Test.name } else { $Test.id }
                        category   = if ($Test.testType) { $Test.testType } else { 'Identity' }
                        testFolder = $Suite.name
                    }
                }
            }
        }

        # Remaining unported PS tests still on disk (skip Custom — surfaced separately below).
        foreach ($TestFolder in $TestFolders) {
            $SuiteName = [System.IO.Path]::GetFileName($TestFolder)
            if ($SuiteName -eq 'Custom') { continue }
            foreach ($Category in @('Identity', 'Devices')) {
                $CatPath = Join-Path $TestFolder $Category
                if (-not [System.IO.Directory]::Exists($CatPath)) { continue }
                foreach ($TestFile in [System.IO.Directory]::EnumerateFiles($CatPath, 'Invoke-CippTest*.ps1', [System.IO.SearchOption]::TopDirectoryOnly)) {
                    $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($TestFile)
                    if ($BaseName -notmatch 'Invoke-CippTest(.+)$') { continue }
                    $TestId = $Matches[1]
                    if ($ById.Contains($TestId)) { continue }  # registry wins

                    $TestContent = [System.IO.File]::ReadAllText($TestFile)
                    $TestName = $TestId
                    if ($TestContent -match '\.SYNOPSIS\s+(.+?)(?=\s+\.|\s+#>|\s+\[)') {
                        $TestName = $Matches[1].Trim()
                    }
                    $ById[$TestId] = [PSCustomObject]@{
                        id         = $TestId
                        name       = $TestName
                        category   = $Category
                        testFolder = $SuiteName
                    }
                }
            }
        }

        $IdentityTests = @($ById.Values | Where-Object { $_.category -eq 'Identity' })
        $DevicesTests = @($ById.Values | Where-Object { $_.category -eq 'Devices' })

        # Build custom tests array from latest custom scripts
        $CustomTestsList = foreach ($CustomTest in @($LatestCustomScripts)) {
            $ScriptGuid = $CustomTest.ScriptGuid
            if ([string]::IsNullOrWhiteSpace($ScriptGuid)) {
                continue
            }

            $TestId = "CustomScript-$ScriptGuid"
            $TestName = if ([string]::IsNullOrWhiteSpace($CustomTest.ScriptName)) { $TestId } else { $CustomTest.ScriptName }

            [PSCustomObject]@{
                id             = $TestId
                name           = $TestName
                category       = 'Custom'
                testFolder     = 'Custom'
                scriptGuid     = $ScriptGuid
                description    = $CustomTest.Description ?? ''
                risk           = $CustomTest.Risk ?? 'Medium'
                enabled        = [bool]$CustomTest.Enabled
                alertOnFailure = [bool]$CustomTest.AlertOnFailure
                version        = $CustomTest.Version
            }
        }

        $Body = [PSCustomObject]@{
            IdentityTests = $IdentityTests
            DevicesTests  = $DevicesTests
            CustomTests   = @($CustomTestsList)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = [PSCustomObject]@{
            Results = "Failed to list available tests: $($ErrorMessage.NormalizedError)"
        }
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = ConvertTo-Json -InputObject $Body -Depth 10
        })
}

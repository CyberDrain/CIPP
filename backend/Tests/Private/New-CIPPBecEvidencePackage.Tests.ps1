BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPBecReport { param($TenantFilter, $CaseId, $UserId, [switch]$IncludeResults) }
    function Set-CIPPBecReport { param($TenantFilter, $CaseId, $Properties, $Results, [switch]$Replace) }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property, $First) }
    # Nothing in the evidence path may touch blob storage any more
    function New-CIPPAzStorageRequest { throw 'blob storage must not be touched' }
    function Write-LogMessage { param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $LogData) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecEvidencePackage.ps1')

    $script:Run = [pscustomobject]@{
        CaseId = 'BEC-20260820120000-ev0001'; Status = 'Completed'; UserPrincipalName = 'victim@contoso.com'; UserId = 'u1'; Scope = 'Full'; ExtractedAt = '2026-08-20T12:05:00Z'; RequestedAt = '2026-08-20T12:00:00Z'; Score = 12; Level = 'High'
        EvidenceExports = @([pscustomobject]@{ At = '2026-08-21T09:00:00Z'; By = 'earlier@msp.com'; Sha256 = 'older000'; Bytes = 100; FileCount = 5; IncludesPdf = $false })
        Containment = @([pscustomobject]@{ At = '2026-08-20T13:00:00Z'; By = 'tech'; DryRun = $false; Actions = @('ResetPassword'); Results = @([pscustomobject]@{ Action = 'ResetPassword'; state = 'success'; resultText = 'The new password is [redacted]' }) })
        Results = [pscustomobject]@{
            CaseId = 'BEC-20260820120000-ev0001'; Scope = 'Full'; ContentPolicy = 'metadata-only'
            NewRules = @([pscustomobject]@{ Name = 'Hide'; RiskReasons = @('Forwards or redirects messages', 'Deletes messages'); Nested = [pscustomobject]@{ a = 1 } })
            Delegations = @([pscustomobject]@{ PermissionType = 'FullAccess'; Trustee = 'x@example.org'; Flagged = $true })
            SentMessages = @()
            RiskState = [pscustomobject]@{ Listed = $true; Detections = @([pscustomobject]@{ RiskEventType = 'unfamiliarFeatures' }) }
            Score = [pscustomobject]@{ Value = 12; Level = 'High' }
        }
    }
    $script:PdfBase64 = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes('%PDF-1.4 fake'))

    function Read-Zip {
        param([byte[]]$Bytes)
        $Stream = [System.IO.MemoryStream]::new($Bytes)
        $Archive = [System.IO.Compression.ZipArchive]::new($Stream, [System.IO.Compression.ZipArchiveMode]::Read)
        $Entries = @{}
        foreach ($Entry in $Archive.Entries) {
            $EntryStream = $Entry.Open()
            $Ms = [System.IO.MemoryStream]::new()
            $EntryStream.CopyTo($Ms)
            $Entries[$Entry.FullName] = $Ms.ToArray()
            $EntryStream.Dispose(); $Ms.Dispose()
        }
        $Archive.Dispose(); $Stream.Dispose()
        $Entries
    }
}

Describe 'New-CIPPBecEvidencePackage' {
    BeforeEach {
        Mock Get-CIPPBecReport { $script:Run }
        $script:Recorded = $null
        Mock Set-CIPPBecReport { $script:Recorded = $Properties }
        Mock Get-CIPPTable { @{ Context = @{ TableName = $TableName } } }
        Mock Get-CIPPAzDataTableEntity {
            @(
                [pscustomobject]@{ Timestamp = '2026-08-20T12:01:00Z'; Tenant = 'contoso.com'; API = 'BECRun'; Severity = 'Info'; Username = 'tech'; Message = 'BEC Check run'; LogData = ''; RowKey = 'l1' }
                [pscustomobject]@{ Timestamp = '2026-08-20T13:00:00Z'; Tenant = 'contoso.com'; API = 'BECRemediate'; Severity = 'Info'; Username = 'tech'; Message = 'Executed containment'; LogData = '[{"Action":"ResetPassword","copyField":"Hunter2!","resultText":"x"}]'; RowKey = 'l2' }
            )
        }
        Mock Write-LogMessage { }
    }

    It 'builds a ZIP whose manifest hashes match every file, stores nothing, and appends the export record to the run' {
        $Package = New-CIPPBecEvidencePackage -TenantFilter 'contoso.com' -CaseId 'BEC-20260820120000-ev0001' -PdfBase64 $script:PdfBase64 -PdfSummaryBase64 $script:PdfBase64
        $Package.ZipSha256 | Should -Match '^[0-9a-f]{64}$'
        $Entries = Read-Zip -Bytes $Package.ZipBytes
        $Entries.Keys | Should -Contain 'results.json'
        $Entries.Keys | Should -Contain 'findings/NewRules.csv'
        $Entries.Keys | Should -Contain 'findings/Delegations.csv'
        $Entries.Keys | Should -Contain 'findings/RiskDetections.csv'
        $Entries.Keys | Should -Not -Contain 'findings/SentMessages.csv' -Because 'empty sections are skipped'
        $Entries.Keys | Should -Contain 'containment.json'
        $Entries.Keys | Should -Contain 'logbook.json'
        $Entries.Keys | Should -Contain 'report-full.pdf'
        $Entries.Keys | Should -Contain 'report-summary.pdf'
        $Entries.Keys | Should -Contain 'manifest.sha256.json'
        $Manifest = [System.Text.Encoding]::UTF8.GetString($Entries['manifest.sha256.json']) | ConvertFrom-Json
        $Manifest.Schema | Should -Be 'cipp-bec-evidence/v1'
        $Manifest.ContentPolicy | Should -Be 'metadata-only'
        $Manifest.Files.Count | Should -Be ($Entries.Count - 1)
        foreach ($File in $Manifest.Files) {
            $Actual = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Entries[$File.Path])).ToLowerInvariant()
            $Actual | Should -Be $File.Sha256 -Because "$($File.Path) must hash as listed"
            $Entries[$File.Path].Length | Should -Be $File.Bytes
        }
        # nothing stored; the export record is appended after the earlier one
        $script:Recorded | Should -Not -BeNullOrEmpty
        $script:Recorded.EvidenceSha256 | Should -Be $Package.ZipSha256
        @($script:Recorded.EvidenceExports).Count | Should -Be 2
        @($script:Recorded.EvidenceExports)[0].Sha256 | Should -Be 'older000'
        @($script:Recorded.EvidenceExports)[-1].Sha256 | Should -Be $Package.ZipSha256
        @($script:Recorded.EvidenceExports)[-1].IncludesPdf | Should -BeTrue
        $script:Recorded.Keys | Should -Not -Contain 'EvidenceBlob'
    }

    It 'flattens arrays and nested objects into CSV cells and marks a PDF-less export as such' {
        $Package = New-CIPPBecEvidencePackage -TenantFilter 'contoso.com' -CaseId 'BEC-20260820120000-ev0001'
        $Entries = Read-Zip -Bytes $Package.ZipBytes
        $Csv = [System.Text.Encoding]::UTF8.GetString($Entries['findings/NewRules.csv'])
        $Csv | Should -Match 'Forwards or redirects messages; Deletes messages'
        $Csv | Should -Match '\{""a"":1\}'
        $Entries.Keys | Should -Not -Contain 'report.pdf'
        @($script:Recorded.EvidenceExports)[-1].IncludesPdf | Should -BeFalse
    }

    It 'scrubs any password copy field from the logbook copy and queries the case id across day partitions' {
        $Package = New-CIPPBecEvidencePackage -TenantFilter 'contoso.com' -CaseId 'BEC-20260820120000-ev0001'
        $Entries = Read-Zip -Bytes $Package.ZipBytes
        $Log = [System.Text.Encoding]::UTF8.GetString($Entries['logbook.json'])
        $Log | Should -Not -Match 'Hunter2'
        $Log | Should -Match '\[redacted\]'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Filter -like "BecCaseId eq 'BEC-20260820120000-ev0001'*" -and $Filter -like "*PartitionKey ge '20260819'*" }
    }

    It 'refuses a non-PDF and an incomplete run without recording anything' {
        { New-CIPPBecEvidencePackage -TenantFilter 'contoso.com' -CaseId 'BEC-20260820120000-ev0001' -PdfBase64 ([Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes('<html>'))) } | Should -Throw '*not a PDF*'
        Mock Get-CIPPBecReport { [pscustomobject]@{ Status = 'Waiting' } }
        { New-CIPPBecEvidencePackage -TenantFilter 'contoso.com' -CaseId 'BEC-x' } | Should -Throw '*only completed runs*'
        Should -Invoke Set-CIPPBecReport -Times 0
    }
}

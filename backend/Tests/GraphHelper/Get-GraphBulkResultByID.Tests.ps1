# Get-GraphBulkResultByID picks one sub-response out of a New-GraphBulkRequest result. -ThrowOnError makes a
# failed sub-request an error instead of an empty body, which callers used to read as "nothing there".

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-GraphBulkResultByID.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    $script:Results = @(
        [pscustomobject]@{ id = 'ok'; status = 200; body = [pscustomobject]@{ value = @('a', 'b') } }
        [pscustomobject]@{ id = 'denied'; status = 403; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Insufficient privileges' } } }
        [pscustomobject]@{ id = 'missing'; status = 404; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'Not found' } } }
        [pscustomobject]@{ id = 'partial'; status = 200; PagingIncomplete = $true; PagingError = 'continuation page returned 429'; body = [pscustomobject]@{ value = @('a') } }
    )
}

Describe 'Get-GraphBulkResultByID' {
    It 'returns the body or its value for a successful sub-request' {
        Get-GraphBulkResultByID -Results $script:Results -ID 'ok' -Value -ThrowOnError | Should -Be @('a', 'b')
        (Get-GraphBulkResultByID -Results $script:Results -ID 'ok').value | Should -Be @('a', 'b')
    }

    It 'keeps returning an empty result for a failed sub-request without -ThrowOnError' {
        Get-GraphBulkResultByID -Results $script:Results -ID 'denied' -Value | Should -BeNullOrEmpty
    }

    It 'throws the Graph error for a failed sub-request' {
        { Get-GraphBulkResultByID -Results $script:Results -ID 'denied' -ThrowOnError } | Should -Throw '*denied*Insufficient privileges*'
    }

    It 'throws a not-found error that maps to 404' {
        try { Get-GraphBulkResultByID -Results $script:Results -ID 'missing' -ThrowOnError } catch { $Err = $_ }
        Get-CippErrorStatusCode -ErrorRecord $Err | Should -Be ([System.Net.HttpStatusCode]::NotFound)
    }

    It 'throws when a continuation page was lost' {
        { Get-GraphBulkResultByID -Results $script:Results -ID 'partial' -Value -ThrowOnError } | Should -Throw '*continuation page returned 429*'
    }

    It 'throws when the sub-request has no response' {
        { Get-GraphBulkResultByID -Results $script:Results -ID 'nope' -ThrowOnError } | Should -Throw '*no response*'
    }
}

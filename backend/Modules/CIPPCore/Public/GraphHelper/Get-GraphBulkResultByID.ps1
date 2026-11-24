function Get-GraphBulkResultByID ($Results, $ID, [switch]$Value, [switch]$ThrowOnError) {
    <#
    .FUNCTIONALITY
    Internal
    .DESCRIPTION
    -ThrowOnError throws when the sub-request is missing, failed (status >= 400) or lost a continuation page,
    instead of handing back an empty body. A 404 throws ItemNotFoundException, so Get-CippErrorStatusCode maps it to 404.
    #>
    $Result = $Results | Where-Object { $_.id -eq $ID }
    if ($ThrowOnError) {
        $Status = $Result.status -as [int]
        if (-not $Result -or $Status -ge 400 -or $Result.PagingIncomplete) {
            $Message = "Graph request '$ID' failed: $($Result.body.error.message ?? $Result.PagingError ?? $(if ($Status) { "HTTP $Status" } else { 'no response' }))"
            if ($Status -eq 404) { throw [System.Management.Automation.ItemNotFoundException]::new($Message) }
            throw $Message
        }
    }
    if ($Value) {
        $Result.body.value
    } else {
        $Result.body
    }
}

function New-CIPPBecCaseId {
    <#
    .SYNOPSIS
        Mints a new BEC case id.
    .DESCRIPTION
        Case ids are BEC-<yyyyMMddHHmmss>-<6 hex>: the timestamp prefix keeps them chronologically
        sortable as table RowKeys (so a user's run history lists in order) and the random suffix keeps
        two runs queued in the same second distinct. The id is stamped on the run row, the results
        blob, every logbook entry written during the case and the evidence manifest.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Suffix = -join ((1..6) | ForEach-Object { '{0:x}' -f (Get-Random -Minimum 0 -Maximum 16) })
    return 'BEC-{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'), $Suffix
}

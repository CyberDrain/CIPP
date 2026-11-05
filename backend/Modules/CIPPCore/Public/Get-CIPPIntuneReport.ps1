function Get-CIPPIntuneReport {
    <#
    .SYNOPSIS
        Reads every row of a synchronous Intune deviceManagement/reports action.
    .DESCRIPTION
        Pages the report (top/skip) and turns its Schema/Values table into one object per row.
    .PARAMETER ReportName
        The report action, e.g. getConfigurationPolicyDevicesReport.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$ReportName,
        [Parameter(Mandatory = $true)][string]$Filter,
        [string[]]$Select = @(),
        [string[]]$OrderBy = @()
    )

    $Uri = "https://graph.microsoft.com/beta/deviceManagement/reports/$ReportName"
    $Rows = [System.Collections.Generic.List[object]]::new()
    $PageSize = 500
    $Skip = 0
    do {
        $Body = @{
            top     = $PageSize
            skip    = $Skip
            select  = $Select
            orderBy = $OrderBy
            search  = ''
            filter  = $Filter
        } | ConvertTo-Json -Compress -Depth 5
        $Page = New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -body $Body
        if ($Page -is [string]) { $Page = $Page | ConvertFrom-Json }

        # Reports come back as a column schema plus positional value arrays
        $Columns = @($Page.Schema.Column)
        foreach ($Values in @($Page.Values)) {
            $Row = [ordered]@{}
            for ($Index = 0; $Index -lt $Columns.Count; $Index++) {
                $Row[$Columns[$Index]] = $Values[$Index]
            }
            $Rows.Add([PSCustomObject]$Row)
        }
        $Skip = $Skip + $PageSize
    } while (@($Page.Values).Count -eq $PageSize -and $Skip -lt [int]$Page.TotalRowCount)
    , @($Rows)
}

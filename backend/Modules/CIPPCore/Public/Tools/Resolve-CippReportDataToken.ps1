function Resolve-CippReportDataToken {
    <#
    .SYNOPSIS
        Resolve &data tokens& in report builder blocks against the reporting database.
    .DESCRIPTION
        A block's text can name reporting-database data with a token, and the value is read here on
        the server when the report renders, so a scheduled run and a preview read the same data:

          &Users&                              the number of rows in that collection
          &Users.displayName&                  the field's distinct values, comma-separated (the first 25)
          &Devices.complianceState=compliant&  the number of rows whose field has that value (* wildcards; != for the rest)
          &Mailboxes.TotalItemSize:sum&        a numeric field's sum, avg, min, max or count of rows carrying it

        Collection names are the reporting database's types, the same names the Database Data block
        offers as sources; fields are case-insensitive and may reach into nested objects with dots.
        A chart with a chartSource of &Devices.operatingSystem& gets one slice per value of that field;
        a table with a dataSource of &Mailboxes& (a filter token works too) gets the rows, each column
        reading the field it names (its `field`, else its header). A token that names nothing is left
        as written, so the mistake shows in the report instead of silently blanking.
    .PARAMETER Blocks
        The enriched blocks, as objects or hashtables. Returned with the tokens replaced in place.
    .PARAMETER TenantFilter
        The tenant whose reporting database answers.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Blocks = @(),
        [Parameter(Mandatory = $true)][string]$TenantFilter
    )

    $Pattern = '(?:&amp;|&)(?<type>[A-Za-z0-9_-]+)(?:\.(?<field>[A-Za-z0-9_.-]+))?(?:(?<op>!=|=)(?<value>[^&]*?))?(?::(?<agg>sum|avg|min|max|count))?(?:&amp;|&)'
    $MaxListed = 25
    $MaxSlices = 8
    $MaxRows = 200

    # One read per collection per render; a collection the database does not hold reads as $null.
    $Cache = @{}
    $RowsOf = {
        param([string]$Type)
        $Key = $Type.ToLowerInvariant()
        if (-not $Cache.ContainsKey($Key)) {
            $Rows = try { @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type) | Where-Object { $null -ne $_ -and $_ -ne $false } } catch { $null }
            $Cache[$Key] = if ($null -eq $Rows) { $null } else { @($Rows) }
        }
        $Cache[$Key]
    }

    # A field's values in one row, following a dotted path and flattening arrays along the way.
    $ValueOf = {
        param($Row, [string]$Path)
        $Current = @($Row)
        foreach ($Segment in $Path.Split('.')) {
            $Current = @(foreach ($Item in $Current) {
                    if ($null -eq $Item) { continue }
                    if ($Item -is [System.Collections.IDictionary]) {
                        $Name = @($Item.Keys) | Where-Object { "$_" -ieq $Segment } | Select-Object -First 1
                        if ($null -ne $Name) { $Item[$Name] }
                    } else {
                        $Property = $Item.PSObject.Properties | Where-Object { $_.Name -ieq $Segment } | Select-Object -First 1
                        if ($Property) { $Property.Value }
                    }
                })
        }
        @($Current | Where-Object { $null -ne $_ -and "$_" -ne '' })
    }

    $RowMatches = {
        param($Row, [string]$Field, [string]$Op, [string]$Wanted)
        $Values = @(& $ValueOf $Row $Field | ForEach-Object { "$_" })
        $Hit = if ($Wanted.Contains('*')) { @($Values | Where-Object { $_ -like $Wanted }).Count -gt 0 } else { @($Values | Where-Object { $_ -ieq $Wanted }).Count -gt 0 }
        if ($Op -eq '!=') { -not $Hit } else { $Hit }
    }

    $FormatNumber = { param([double]$n) if ([math]::Round($n) -eq $n) { "$([long]$n)" } else { "$([math]::Round($n, 2))" } }

    # The text a token stands for; $null when its collection is unknown, so the token stays as written.
    $Evaluate = {
        param($Match)
        $Type = $Match.Groups['type'].Value
        $Field = $Match.Groups['field'].Value
        $Op = $Match.Groups['op'].Value
        $Wanted = $Match.Groups['value'].Value
        $Agg = $Match.Groups['agg'].Value
        $Rows = & $RowsOf $Type
        if ($null -eq $Rows) { return $null }
        if (-not $Field) { return "$($Rows.Count)" }
        if ($Op) { return "$(@($Rows | Where-Object { & $RowMatches $_ $Field $Op $Wanted }).Count)" }
        $Values = @(foreach ($Row in $Rows) { & $ValueOf $Row $Field })
        if ($Agg) {
            if ($Agg -eq 'count') { return "$($Values.Count)" }
            $Numbers = @($Values | ForEach-Object { $_ -as [double] } | Where-Object { $null -ne $_ })
            if ($Numbers.Count -eq 0) { return '0' }
            $Measured = $Numbers | Measure-Object -Sum -Average -Minimum -Maximum
            $Aggregate = switch ($Agg) { 'sum' { $Measured.Sum } 'avg' { $Measured.Average } 'min' { $Measured.Minimum } default { $Measured.Maximum } }
            return (& $FormatNumber $Aggregate)
        }
        $Distinct = @($Values | ForEach-Object { "$_" } | Sort-Object -Unique)
        if ($Distinct.Count -le $MaxListed) { return ($Distinct -join ', ') }
        return (($Distinct | Select-Object -First $MaxListed) -join ', ') + " and $($Distinct.Count - $MaxListed) more"
    }

    # Replace every token in a string. A string that is one token and resolves to a number becomes a
    # number, so a progress bar's value or a chart point can be a token too.
    $ReplaceIn = {
        param([string]$Text)
        if ($Text -notmatch '&') { return $Text }
        $Whole = [regex]::Match($Text.Trim(), "^$Pattern$")
        $Result = [regex]::Replace($Text, $Pattern, [System.Text.RegularExpressions.MatchEvaluator] {
                param($m)
                $Value = & $Evaluate $m
                if ($null -eq $Value) { $m.Value } else { $Value }
            })
        if ($Whole.Success -and $Result.Trim() -match '^-?\d+(\.\d+)?$') { return [double]$Result.Trim() }
        $Result
    }

    $SetProperty = {
        param($Target, [string]$Name, $Value)
        if ($Target -is [System.Collections.IDictionary]) { $Target[$Name] = $Value } else { $Target | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
    }

    # Walk a value: strings are resolved, lists and objects walked, everything else kept.
    $Walk = $null
    $Walk = {
        param($Value)
        if ($Value -is [string]) { return (& $ReplaceIn $Value) }
        if ($Value -is [System.Collections.IDictionary]) {
            foreach ($Name in @($Value.Keys)) { $Value[$Name] = & $Walk $Value[$Name] }
            return $Value
        }
        if ($Value -is [array] -or $Value -is [System.Collections.IList]) {
            return , @(foreach ($Item in $Value) { & $Walk $Item })
        }
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            foreach ($Property in @($Value.PSObject.Properties)) { $Value.($Property.Name) = & $Walk $Property.Value }
            return $Value
        }
        $Value
    }

    $ParseToken = { param([string]$Text) $m = [regex]::Match("$Text".Trim(), "^$Pattern$"); if ($m.Success) { $m } }

    foreach ($Block in @($Blocks)) {
        if ($null -eq $Block) { continue }
        $Type = "$($Block.type)"

        # A chart drawn from the data: one slice per distinct value of the field, the long tail as Other.
        if ($Type -eq 'chart' -and $Block.chartSource) {
            $Source = & $ParseToken $Block.chartSource
            $Rows = if ($Source) { & $RowsOf $Source.Groups['type'].Value }
            if ($Source -and $null -ne $Rows) {
                $Field = $Source.Groups['field'].Value
                $Op = $Source.Groups['op'].Value
                $Points = if ($Field -and -not $Op) {
                    $Groups = @(foreach ($Row in $Rows) { @(& $ValueOf $Row $Field | ForEach-Object { "$_" }) }) | Group-Object { $_.ToLowerInvariant() } | Sort-Object -Property Count -Descending
                    $Blank = @($Rows | Where-Object { @(& $ValueOf $_ $Field).Count -eq 0 }).Count
                    $Top = @($Groups | Select-Object -First $MaxSlices | ForEach-Object { @{ label = $_.Group[0]; value = $_.Count } })
                    $Rest = @($Groups | Select-Object -Skip $MaxSlices | Measure-Object -Property Count -Sum).Sum
                    @($Top; if ($Rest -gt 0) { @{ label = 'Other'; value = [int]$Rest } }; if ($Blank -gt 0) { @{ label = '(blank)'; value = $Blank } })
                } else {
                    $Count = if ($Op) { @($Rows | Where-Object { & $RowMatches $_ $Field $Op $Source.Groups['value'].Value }).Count } else { $Rows.Count }
                    @(@{ label = $(if ($Block.title) { "$($Block.title)" } else { $Source.Groups['type'].Value }); value = $Count })
                }
                & $SetProperty $Block 'chartData' @($Points)
            }
        }

        # A table filled from the data: the rows (or the ones a filter token keeps), each column
        # reading the field it names.
        if ($Type -eq 'richtable' -and $Block.dataSource) {
            $Source = & $ParseToken $Block.dataSource
            $Rows = if ($Source) { & $RowsOf $Source.Groups['type'].Value }
            if ($Source -and $null -ne $Rows) {
                $Field = $Source.Groups['field'].Value
                $Op = $Source.Groups['op'].Value
                if ($Field -and $Op) { $Rows = @($Rows | Where-Object { & $RowMatches $_ $Field $Op $Source.Groups['value'].Value }) }
                $Columns = @($Block.columns)
                $TableRows = @(foreach ($Row in ($Rows | Select-Object -First $MaxRows)) {
                        $Cells = [ordered]@{}
                        foreach ($Column in $Columns) {
                            $Key = "$($Column.key)"
                            $From = if ($Column.field) { "$($Column.field)" } else { "$($Column.header)" }
                            $Cells[$Key] = (@(& $ValueOf $Row $From | ForEach-Object { "$_" }) -join ', ')
                        }
                        $Cells
                    })
                & $SetProperty $Block 'rows' @($TableRows)
                if (-not $Block.limit) { & $SetProperty $Block 'limit' $MaxRows }
            }
        }

        # Every other string on the block, its rows and its items.
        if ($Block -is [System.Collections.IDictionary]) {
            foreach ($Name in @($Block.Keys)) { if ($Name -notin 'chartSource', 'dataSource') { $Block[$Name] = & $Walk $Block[$Name] } }
        } else {
            foreach ($Property in @($Block.PSObject.Properties)) { if ($Property.Name -notin 'chartSource', 'dataSource') { $Block.($Property.Name) = & $Walk $Property.Value } }
        }
    }

    return , @($Blocks)
}

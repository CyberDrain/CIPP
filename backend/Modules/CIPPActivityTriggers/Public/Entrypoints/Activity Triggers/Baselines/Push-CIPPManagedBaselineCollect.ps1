function Push-CIPPManagedBaselineCollect {
    <#
    .SYNOPSIS
        Durable activity: compare one standard against one tenant for a custom managed baseline request.
    .DESCRIPTION
        One part of the snapshot a custom request sends to CyberDrain. Grades the standard
        against CIPP's own default settings in the engine's compare-only mode, so nothing is
        written to alignment or history, then stores the redacted result as one row of the
        request's collection. A standard that needs a template, or a value only a person can
        choose, is recorded as 'Needs a choice' without reading anything from the tenant.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $Status = 'No Data'
    $Current = $null
    $DiffersOn = [System.Collections.Generic.List[string]]::new()
    try {
        $Definition = Get-CIPPBaselineDefinition -Name $Item.Standard | Select-Object -First 1
        if (-not $Definition) { throw "No definition found for standard $($Item.Standard)." }

        # The engine's own rule for a setting it cannot fill in: no default, and either required
        # or still present in the expected value.
        $ExpectedJson = ''
        if ($null -ne $Definition.expected) { $ExpectedJson = ConvertTo-Json -Compress -Depth 100 -InputObject $Definition.expected }
        $NeedsChoice = [bool]$Definition.instanceIdentity
        foreach ($Variable in (($Definition.variables ?? [PSCustomObject]@{}).PSObject.Properties)) {
            if ($null -ne ($Variable.Value.default ?? $Variable.Value.recommended)) { continue }
            if ($Variable.Value.required -eq $true -or ($Variable.Value.omitWhenBlank -ne $true -and $ExpectedJson.Contains(('%{0}%' -f $Variable.Name)))) {
                $NeedsChoice = $true
                break
            }
        }

        if ($NeedsChoice) {
            $Status = 'Needs a choice'
        } else {
            $WorkItem = @{
                TenantFilter     = "$($Item.TenantFilter)"
                TenantName       = "$($Item.TenantFilter)"
                Standard         = "$($Item.Standard)"
                BaseName         = "$($Item.Standard)"
                Variables        = $null
                Tiers            = @()
                Stage            = 1
                StageName        = ''
                TemplateId       = ''
                SourceScope      = 'managed'
                SourceTemplate   = 'Managed baseline snapshot'
                RemediateEnabled = $false
                AlertEnabled     = $false
            }
            $Graded = Invoke-CIPPBaselineStandard -Item $WorkItem -Mode 'compare' -GradeOnly
            if ($null -eq $Graded) {
                $Status = 'No Data'
            } elseif ($Graded.PSObject.Properties['Outcome']) {
                # A full result means the engine stopped before grading and says why.
                if ("$($Graded.Status)" -eq 'Skipped - No License') { $Status = 'No licence' }
            } elseif ($null -ne $Graded.CurrentValue) {
                $Status = $Graded.Compliant ? 'Compliant' : 'Drift'
                $Current = Protect-CIPPManagedBaselineSnapshot -Value $Graded.CurrentValue -TenantIdentifiers @($Item.TenantIdentifiers) -Definition $Definition
                foreach ($Difference in @($Graded.Diff)) {
                    if (-not $Difference.Property) { continue }
                    $Property = "$(Protect-CIPPManagedBaselineSnapshot -Value "$($Difference.Property)" -TenantIdentifiers @($Item.TenantIdentifiers) -Definition $Definition)"
                    if (-not $DiffersOn.Contains($Property)) { $DiffersOn.Add($Property) }
                }
            }
        }
    } catch {
        $Status = 'No Data'
        Write-Information "Managed baseline snapshot: $($Item.Standard) on $($Item.TenantFilter) could not be compared: $($_.Exception.Message)"
    } finally {
        $CurrentJson = ''
        if ($null -ne $Current) {
            $CurrentJson = ConvertTo-Json -Compress -Depth 100 -InputObject $Current
            # One table property holds 32K characters; a value that large is not a setting.
            if ($CurrentJson.Length -gt 30000) { $CurrentJson = '"<too large to send>"' }
        }
        $Table = Get-CippTable -tablename 'ManagedBaselineCollection'
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = "$($Item.RequestId)"
            RowKey       = "$($Item.Standard)"
            Status       = $Status
            InBaseline   = [bool]$Item.InBaseline
            Current      = $CurrentJson
            DiffersOn    = [string](ConvertTo-Json -Compress -InputObject @($DiffersOn))
        } -Force
        if ($Item.QueueId) {
            $null = Update-CippQueueEntry -RowKey $Item.QueueId -Status 'Running' -Name $Item.QueueName
        }
    }
}

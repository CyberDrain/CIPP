function Test-DeltaQueryConditions {
    <#
    .SYNOPSIS
        Tests if the conditions for a Delta Query trigger are met.
    .DESCRIPTION
        This function evaluates whether the specified conditions for a Delta Query trigger are satisfied based on the provided data.
    .PARAMETER Query
        The result of the delta query to evaluate.
    .PARAMETER Trigger
        The trigger configuration containing conditions to test against.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Query,
        [Parameter(Mandatory = $true)]
        $Trigger,
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        [Parameter(Mandatory = $true)]
        $LastTrigger
    )

    $ConditionsMet = $false
    $MatchedData = @()

    $Data = $Query.value
    $EventType = $Trigger.EventType.value ?? $Trigger.EventType

    # Filter data based on delta query change type according to Microsoft Graph specification
    switch ($EventType) {
        'deleted' {
            Write-Information "data to process for deleted: $($Data | ConvertTo-Json -Depth 5)"
            # Removed instances are represented by their id and an @removed object. Graph sets reason 'changed'
            # for a soft delete (restorable, still in directory/deletedItems) and 'deleted' for a permanent one.
            # Resources with a recycle bin report the soft delete first, so their later purge ('deleted') would fire
            # the trigger twice. A 'deleted' group row carries only its id, so a security group's permanent delete
            # can't be told apart from an M365 group's purge and stays unmatched.
            $Resource = $Trigger.DeltaResource.value ?? $Trigger.DeltaResource
            $SoftDeletable = @('users', 'groups', 'applications', 'servicePrincipals', 'administrativeUnits', 'directoryObjects')
            $AcceptedReasons = $Resource -in $SoftDeletable ? @('changed') : @('changed', 'deleted')
            $Data = $Data | Where-Object {
                $_.PSObject.Properties.Name -contains '@removed' -and $_.'@removed'.reason -in $AcceptedReasons
            }

            # For soft-deleted directory objects, fetch full details from deletedItems
            Write-Information 'Fetching full details for deleted directory objects.'

            $Requests = foreach ($item in $Data) {
                if ($item.'@removed'.reason -ne 'changed') { continue }
                [PSCustomObject]@{
                    'id'     = $item.id
                    'url'    = "directory/deletedItems/$($item.id)"
                    'method' = 'GET'
                }
            }
            if ($Requests) {
                try {
                    $DeletedItems = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter
                    if ($DeletedItems.status -eq 200) {
                        Write-Information 'Retrieved full details for deleted items.'
                        Write-Information "Deleted items response: $($DeletedItems | ConvertTo-Json -Depth 5)"
                        $EnrichedData = [System.Collections.Generic.List[object]]::new()
                        foreach ($Row in $Data) {
                            $fullItem = ($DeletedItems | Where-Object { $_.id -eq $Row.id -and $_.status -eq 200 }).body
                            if ($fullItem) {
                                $EnrichedData.Add($fullItem)
                            } else {
                                $EnrichedData.Add($Row)
                            }
                        }
                        $Data = $EnrichedData
                    }
                } catch {
                    Write-Warning "Failed to retrieve full details for deleted items: $($_.Exception.Message)"
                }
            }

            Write-Information "Found $($Data.Count) deleted items."
        }
        'created' {
            # Newly created instances use standard representation without @removed
            # These will have their full standard representation, not minimal response
            $Data = $Data | Where-Object { $_.createdDateTime -ge $LastTrigger }
            Write-Information "Found $($Data.Count) created items."
        }
        'updated' {
            # Updated instances have at least updated properties but no @removed object
            $Data = $Data | Where-Object {
                $_.PSObject.Properties.Name -notcontains '@removed' -and
                (!$_.createdDateTime -or $_.createdDateTime -lt $LastTrigger)
            }
            Write-Information "Found $($Data.Count) updated items."
        }
    }

    # Check if we have any data after event type filtering
    if (($Data | Measure-Object).Count -eq 0) {
        Write-Information "No data matches the event type filter '$EventType'. Conditions not met."
        return @{
            ConditionsMet     = $false
            MatchedData       = @()
            TotalItems        = ($Query.value | Measure-Object).Count
            FilteredItems     = 0
            MatchedItems      = 0
            EventTypeFilter   = $EventType
            ChangeTypeSummary = @()
        }
    }

    if ($Trigger.UseConditions -eq $true -and ($Trigger.Conditions -or $Trigger.DeltaConditions)) {
        try {
            $conditions = if ($Trigger.DeltaConditions) {
                # The scheduler form saves {Property, Operator: {label, value}, Value}; map it to the
                # {Property.label, Operator.value, Input.value} shape Test-CIPPConditionFilter reads
                $DeltaConditions = $Trigger.DeltaConditions -is [string] ? ($Trigger.DeltaConditions | ConvertFrom-Json) : $Trigger.DeltaConditions
                foreach ($DeltaCondition in @($DeltaConditions)) {
                    [PSCustomObject]@{
                        Property = [PSCustomObject]@{ label = $DeltaCondition.Property.label ?? $DeltaCondition.Property }
                        Operator = [PSCustomObject]@{ label = $DeltaCondition.Operator.label ?? $DeltaCondition.Operator; value = $DeltaCondition.Operator.value ?? $DeltaCondition.Operator }
                        Input    = [PSCustomObject]@{ value = $DeltaCondition.Value.value ?? $DeltaCondition.Value }
                    }
                }
            } else {
                # Parse conditions from JSON (similar to audit log processing)
                $Trigger.Conditions | ConvertFrom-Json
            }
            $conditions = $conditions | Where-Object { $_.Input.value -ne '' -and $null -ne $_.Input.value }

            if ($conditions) {
                # Build human-readable clause for logging
                $CIPPClause = [System.Collections.Generic.List[string]]::new()
                foreach ($condition in $conditions) {
                    $CIPPClause.Add("$($condition.Property.label) is $($condition.Operator.label) $($condition.Input.value)")
                }
                Write-Information "Testing delta query conditions: $($CIPPClause -join ' and ')"

                # Build sanitized condition strings instead of direct evaluation
                $conditionStrings = [System.Collections.Generic.List[string]]::new()
                $validConditions = $true
                foreach ($condition in $conditions) {
                    $sanitized = Test-CIPPConditionFilter -Condition $condition
                    if ($null -eq $sanitized) {
                        Write-Warning "Skipping due to invalid condition for property '$($condition.Property.label)'"
                        $validConditions = $false
                        break
                    }
                    $conditionStrings.Add($sanitized)
                }

                if ($validConditions -and $conditionStrings.Count -gt 0) {
                    $WhereString = $conditionStrings -join ' -and '
                    $WhereBlock = [ScriptBlock]::Create($WhereString)
                    $MatchedData = $Data | Where-Object $WhereBlock
                } else {
                    $MatchedData = @()
                }
            } else {
                Write-Information 'No valid conditions found in trigger configuration.'
                $MatchedData = $Data
            }
        } catch {
            Write-Warning "Error processing delta query conditions: $($_.Exception.Message)"
            Write-Information $_.InvocationInfo.PositionMessage
            $MatchedData = @()
        }
    } else {
        # No conditions specified, consider all data as matching
        $MatchedData = $Data
    }

    # Determine if conditions are met based on final matched data count
    $ConditionsMet = ($MatchedData | Measure-Object).Count -gt 0

    # Return results with matched data and change type summary
    $changeTypeSummary = $MatchedData | Group-Object CIPPChangeType | ForEach-Object {
        @{
            ChangeType = $_.Name
            Count      = $_.Count
        }
    }

    return @{
        ConditionsMet     = $ConditionsMet
        MatchedData       = $MatchedData
        TotalItems        = ($Query.value | Measure-Object).Count
        FilteredItems     = ($Data | Measure-Object).Count
        MatchedItems      = ($MatchedData | Measure-Object).Count
        EventTypeFilter   = $EventType
        ChangeTypeSummary = $changeTypeSummary
    }

}

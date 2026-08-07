function Import-CommunityTemplate {
    <#

    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Template,
        $SHA,
        $MigrationTable,
        $LocationData,
        $Source,
        [switch]$Force
    )

    $Table = Get-CippTable -TableName 'templates'
    $StatusMessage = $null

    try {
        if ($Template.RowKey) {
            Write-Host "This is going to be a direct write to table, it's a CIPP template. We're writing $($Template.RowKey)"
            $Template = $Template | Select-Object * -ExcludeProperty Timestamp

            # Support both objects and json string in repo (support pretty printed json in repo)
            if (Test-Json $Template.JSON -ErrorAction SilentlyContinue) {
                $NewJSON = $Template.JSON | ConvertFrom-Json
            } else {
                $NewJSON = $Template.JSON
            }

            # Check for existing object
            $Existing = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($Template.RowKey)' and PartitionKey eq '$($Template.PartitionKey)'" -ErrorAction SilentlyContinue

            # Nothing to import when the repo file has not moved since it was last read. The write
            # below is a full replace keyed on RowKey, so going ahead anyway cannot add anything -
            # it can only overwrite edits made in CIPP since then with the older repo copy. The
            # template sync reaches this path automatically for any file it fails to match by name,
            # so without this guard a stale file silently reverts a live template on a schedule.
            # Matches the behaviour the community template path below already has.
            if ($Existing -and $SHA -and $Existing.SHA -eq $SHA -and -not $Force) {
                $StatusMessage = "Template '$($Template.RowKey)' from source '$Source' is already up to date. Skipping import."
                Write-Information $StatusMessage
                return $StatusMessage
            }

            if ($Existing) {
                if ($Existing.PartitionKey -eq 'StandardsTemplateV2') {
                    # Convert existing JSON to object for updates
                    if (Test-Json $Existing.JSON -ErrorAction SilentlyContinue) {
                        $ExistingJSON = $Existing.JSON | ConvertFrom-Json
                    } else {
                        $ExistingJSON = $Existing.JSON
                    }
                    # Extract existing tenantFilter and excludedTenants
                    $tenantFilter = $ExistingJSON.tenantFilter
                    $excludedTenants = $ExistingJSON.excludedTenants
                    $NewJSON.tenantFilter = $tenantFilter
                    $NewJSON.excludedTenants = $excludedTenants
                }
            }

            if ($Template.PartitionKey -eq 'AppApprovalTemplate') {
                # Extract the Permission Set name,id,permissions from the JSON and add to the AppPermissions table
                $AppPermissionsTable = Get-CIPPTable -TableName 'AppPermissions'
                $Permissions = $NewJSON.Permissions
                $Entity = @{
                    'PartitionKey' = 'Templates'
                    'RowKey'       = $NewJSON.PermissionSetId
                    'TemplateName' = $NewJSON.PermissionSetName
                    'Permissions'  = [string]($Permissions | ConvertTo-Json -Depth 10 -Compress)
                    'UpdatedBy'    = $NewJSON.UpdatedBy ?? $NewJSON.CreatedBy ?? 'System'
                }
                $null = Add-CIPPAzDataTableEntity @AppPermissionsTable -Entity $Entity -Force
                Write-Information 'Added App Permissions to AppPermissions table'
            }

            # Re-compress JSON and save to table
            $NewJSON = [string]($NewJSON | ConvertTo-Json -Depth 100 -Compress)
            $Template.JSON = $NewJSON
            $Template | Add-Member -MemberType NoteProperty -Name SHA -Value $SHA -Force
            $Template | Add-Member -MemberType NoteProperty -Name Source -Value $Source -Force

            # This is a replace, not a merge, so any column the repo file does not carry is lost.
            # Package membership is assigned locally and is usually set after a template was last
            # uploaded, so importing would quietly drop the template out of its package - the
            # standards engine resolves packages by filtering on this column, and the template
            # would simply stop being evaluated. Keep what is already stored unless the incoming
            # file sets it explicitly.
            if ($Existing.Package -and [string]::IsNullOrWhiteSpace($Template.Package)) {
                $Template | Add-Member -MemberType NoteProperty -Name Package -Value $Existing.Package -Force
            }

            Add-CIPPAzDataTableEntity @Table -Entity $Template -Force

            if ($Existing -and $Existing.SHA -ne $SHA) {
                $StatusMessage = "Updated template '$($Template.RowKey)' from source '$Source' (SHA changed)."
            } elseif ($Existing) {
                $StatusMessage = "Template '$($Template.RowKey)' from source '$Source' is already up to date."
            } else {
                $StatusMessage = "Created template '$($Template.RowKey)' from source '$Source'."
            }
        } else {
            $id = [guid]::NewGuid().ToString()
            if ($Template.mailNickname) { $Type = 'Group' }
            if ($Template.'@odata.type' -like '*conditionalAccessPolicy*') { $Type = 'ConditionalAccessPolicy' }
            Write-Host "The type is $Type"

            switch -Wildcard ($Type) {
                '*Group*' {
                    # Check for duplicate template
                    $DuplicateFilter = "PartitionKey eq 'GroupTemplate'"
                    $ExistingTemplates = Get-CIPPAzDataTableEntity @Table -Filter $DuplicateFilter -ErrorAction SilentlyContinue
                    $Duplicate = $ExistingTemplates | Where-Object {
                        try {
                            $ExistingJSON = if (Test-Json $_.JSON -ErrorAction SilentlyContinue) {
                                $_.JSON | ConvertFrom-Json
                            } else {
                                $_.JSON
                            }
                            $ExistingJSON.Displayname -eq $Template.displayName -and $_.Source -eq $Source
                        } catch {
                            $false
                        }
                    } | Select-Object -First 1

                    if ($Duplicate -and $Duplicate.SHA -eq $SHA -and -not $Force) {
                        $StatusMessage = "Group template '$($Template.displayName)' from source '$Source' is already up to date. Skipping import."
                        Write-Information $StatusMessage
                        break
                    }

                    # On update, reuse the existing GUID so the JSON-embedded GUID stays in
                    # sync with the table RowKey (see the Intune path below for the full rationale).
                    $TemplateGuid = if ($Duplicate) { $Duplicate.GUID } else { $id }

                    $RawJsonObj = [PSCustomObject]@{
                        Displayname     = $Template.displayName
                        Description     = $Template.Description
                        MembershipRules = $Template.membershipRule
                        username        = $Template.mailNickname
                        GUID            = $TemplateGuid
                        groupType       = 'generic'
                    } | ConvertTo-Json -Depth 100

                    if ($Duplicate) {
                        $StatusMessage = "Updating Group template '$($Template.displayName)' from source '$Source' (SHA changed)."
                        Write-Information $StatusMessage
                    } else {
                        $StatusMessage = "Created Group template '$($Template.displayName)' from source '$Source'."
                    }

                    $entity = @{
                        JSON         = "$RawJsonObj"
                        PartitionKey = 'GroupTemplate'
                        SHA          = $SHA
                        GUID         = $TemplateGuid
                        RowKey       = if ($Duplicate) { $Duplicate.RowKey } else { $id }
                        Source       = $Source
                    }
                    Add-CIPPAzDataTableEntity @Table -Entity $entity -Force
                    break
                }
                '*conditionalAccessPolicy*' {
                    Write-Host $MigrationTable
                    $Template = ([pscustomobject]$Template) | ForEach-Object {
                        $NonEmptyProperties = $_.psobject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name
                        $_ | Select-Object -Property $NonEmptyProperties
                    }
                    $Template = $Template | Select-Object * -ExcludeProperty lastModifiedDateTime, 'assignments', '#microsoft*', '*@odata.navigationLink', '*@odata.associationLink', '*@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime', '@odata.id', '@odata.editLink', '*odata.type', 'roleScopeTagIds@odata.type', createdDateTime, 'createdDateTime@odata.type', 'templateId'
                    Remove-ODataProperties -Object $Template

                    $LocationInfo = [system.collections.generic.list[object]]::new()
                    if ($LocationData) {
                        $LocationData | ForEach-Object {
                            if ($Template.conditions.locations.includeLocations -contains $_.id -or $Template.conditions.locations.excludeLocations -contains $_.id) {
                                Write-Information "Adding location info for location ID $($_.id)"
                                $LocationInfo.Add($_)
                            }
                        }
                        if ($LocationInfo.Count -gt 0) {
                            $Template | Add-Member -MemberType NoteProperty -Name LocationInfo -Value $LocationInfo -Force
                        }
                    }

                    $RawJson = ConvertTo-Json -InputObject $Template -Depth 100 -Compress

                    Write-Information "Raw JSON before ID replacement: $RawJson"
                    #Replace the ids with the displayname by using the migration table, this is a simple find and replace each instance in the JSON.
                    $MigrationTable.objects | ForEach-Object {
                        if ($RawJson -match $_.ID) {
                            $RawJson = $RawJson.Replace($_.ID, $($_.DisplayName))
                        }
                    }

                    # Check for duplicate template
                    $DuplicateFilter = "PartitionKey eq 'CATemplate'"
                    $ExistingTemplates = Get-CIPPAzDataTableEntity @Table -Filter $DuplicateFilter -ErrorAction SilentlyContinue
                    $Duplicate = $ExistingTemplates | Where-Object {
                        try {
                            $ExistingJSON = if (Test-Json $_.JSON -ErrorAction SilentlyContinue) {
                                $_.JSON | ConvertFrom-Json
                            } else {
                                $_.JSON
                            }
                            $ExistingJSON.displayName -eq $Template.displayName -and $_.Source -eq $Source
                        } catch {
                            $false
                        }
                    } | Select-Object -First 1

                    if ($Duplicate -and $Duplicate.SHA -eq $SHA -and -not $Force) {
                        $StatusMessage = "Conditional Access template '$($Template.displayName)' from source '$Source' is already up to date. Skipping import."
                        Write-Information $StatusMessage
                        break
                    }

                    if ($Duplicate) {
                        $StatusMessage = "Updating Conditional Access template '$($Template.displayName)' from source '$Source' (SHA changed)."
                        Write-Information $StatusMessage
                    } else {
                        $StatusMessage = "Created Conditional Access template '$($Template.displayName)' from source '$Source'."
                    }

                    $entity = @{
                        JSON         = "$RawJson"
                        PartitionKey = 'CATemplate'
                        SHA          = $SHA
                        GUID         = if ($Duplicate) { $Duplicate.GUID } else { $id }
                        RowKey       = if ($Duplicate) { $Duplicate.RowKey } else { $id }
                        Source       = $Source
                    }
                    Write-Information "Final entity: $($entity | ConvertTo-Json -Depth 10)"

                    Add-CIPPAzDataTableEntity @Table -Entity $entity -Force
                    break
                }
                default {
                    $URLName = switch -Wildcard ($Template.'@odata.id') {
                        '*CompliancePolicies*' { 'DeviceCompliancePolicies' }
                        '*deviceConfigurations*' { 'Device' }
                        '*DriverUpdateProfiles*' { 'windowsDriverUpdateProfiles' }
                        '*SettingsCatalog*' { 'Catalog' }
                        '*configurationPolicies*' { 'Catalog' }
                        '*managedAppPolicies*' { 'AppProtection' }
                        '*deviceAppManagement*' { 'AppProtection' }
                    }

                    # Fallback: infer type from template content when @odata.id is missing or
                    # unrecognized. The same inference the read paths use, rather than a second copy
                    # of the rules that drifts from it.
                    if (-not $URLName) {
                        $URLName = Get-CIPPIntuneTemplateType -RawJson $Template
                        if ($URLName) {
                            Write-Information "Inferred Intune template type '$URLName' from content structure for '$($Template.displayName ?? $Template.Name)'"
                        }
                    }

                    $RawJson = $Template | Select-Object * -ExcludeProperty id, lastModifiedDateTime, 'assignments', '#microsoft*', '*@odata.navigationLink', '*@odata.associationLink', '*@odata.context', 'ScopeTagIds', 'supportsScopeTags', 'createdDateTime', '@odata.id', '@odata.editLink', 'lastModifiedDateTime@odata.type', 'roleScopeTagIds@odata.type', createdDateTime, 'createdDateTime@odata.type'
                    Remove-ODataProperties -Object $RawJson
                    $RawJson = $RawJson | ConvertTo-Json -Depth 100 -Compress

                    #create a new template
                    $DisplayName = $Template.displayName ?? $template.Name

                    # Refuse a template that cannot deploy rather than storing it. An unmappable
                    # policy used to import cleanly with no type at all, list like any other, and
                    # then deploy to nothing while reporting success - so the repo looked synced and
                    # the tenant was never configured. Failing the file here names the problem while
                    # there is still something to fix it against.
                    $Validation = Test-CIPPIntuneTemplate -RawJSON $RawJson -TemplateType $URLName -DisplayName $DisplayName
                    if (-not $Validation.IsValid) {
                        $StatusMessage = "Intune template '$DisplayName' from source '$Source' was not imported: $($Validation.Errors -join ' ')"
                        Write-Warning $StatusMessage
                        return $StatusMessage
                    }
                    foreach ($Warning in $Validation.Warnings) {
                        Write-Information "Intune template '$DisplayName': $Warning"
                    }

                    # Check for duplicate template
                    $DuplicateFilter = "PartitionKey eq 'IntuneTemplate'"
                    $ExistingTemplates = Get-CIPPAzDataTableEntity @Table -Filter $DuplicateFilter -ErrorAction SilentlyContinue
                    $Duplicate = $ExistingTemplates | Where-Object {
                        try {
                            $ExistingJSON = if (Test-Json $_.JSON -ErrorAction SilentlyContinue) {
                                $_.JSON | ConvertFrom-Json
                            } else {
                                $_.JSON
                            }
                            $ExistingJSON.Displayname -eq $DisplayName -and $_.Source -eq $Source
                        } catch {
                            $false
                        }
                    } | Select-Object -First 1

                    # On update, reuse the existing template's GUID so the GUID embedded
                    # in the JSON blob stays in sync with the table RowKey. Minting a fresh
                    # GUID here desyncs the two: the standards engine resolves templates by
                    # RowKey, while the template picker surfaces the JSON GUID, so the drift
                    # would point at a GUID that no longer matches any RowKey.
                    $TemplateGuid = if ($Duplicate) { $Duplicate.GUID } else { $id }

                    $RawJsonObj = [PSCustomObject]@{
                        Displayname = $DisplayName
                        Description = $Template.Description
                        RAWJson     = $RawJson
                        Type        = $URLName
                        GUID        = $TemplateGuid
                    } | ConvertTo-Json -Depth 100 -Compress

                    if ($Duplicate -and $Duplicate.SHA -eq $SHA -and -not $Force) {
                        $StatusMessage = "Intune template '$DisplayName' from source '$Source' is already up to date. Skipping import."
                        Write-Information $StatusMessage
                        return $StatusMessage
                    }

                    if ($Duplicate) {
                        $StatusMessage = "Updating Intune template '$DisplayName' from source '$Source' (SHA changed)."
                        Write-Information $StatusMessage
                    } else {
                        $StatusMessage = "Created Intune template '$DisplayName' from source '$Source'."
                    }

                    $entity = @{
                        JSON         = "$RawJsonObj"
                        PartitionKey = 'IntuneTemplate'
                        SHA          = $SHA
                        GUID         = $TemplateGuid
                        RowKey       = if ($Duplicate) { $Duplicate.RowKey } else { $id }
                        Source       = $Source
                    }

                    if ($Existing -and $Existing.Package) {
                        $entity.Package = $Existing.Package
                    }

                    if ($Duplicate -and $Duplicate.Package) {
                        $entity.Package = $Duplicate.Package
                    }

                    Add-CIPPAzDataTableEntity @Table -Entity $entity -Force

                }
            }
        }
    } catch {
        $StatusMessage = "Community template import failed. Error: $($_.Exception.Message)"
        Write-Warning $StatusMessage
        Write-Information $_.InvocationInfo.PositionMessage
    }

    return $StatusMessage
}

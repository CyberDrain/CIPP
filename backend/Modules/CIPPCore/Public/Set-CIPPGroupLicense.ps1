function Set-CIPPGroupLicense {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][string]$GroupId,
        [string]$GroupName,
        [array]$AddLicenses = @(),
        [array]$RemoveLicenses = @(),
        [switch]$Replace,
        # skuId -> service plans to disable on that SKU. Arrives as the JSON body object (PSCustomObject) from
        # the forms or a hashtable from scripts; values are bare plan ids or autocomplete options ({ value = id }).
        $DisabledPlans,
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        $Headers,
        $APIName = 'Set Group License'
    )

    $AddLicenses = @(
    $AddLicenses |
        ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $RemoveLicenses = @(
    $RemoveLicenses |
        ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ( [string]::IsNullOrWhiteSpace($GroupName)) {
        $GroupName = $GroupId
    }

    # fetch current assigned licenses, calculate the diff and replace with licenses.
    # Diffs by skuId only: a SKU that is already assigned is dropped from the add list even if its
    # disabled plans differ. No caller passes -Replace today.
    if ($Replace.IsPresent) {
        try {
            $Current = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupId)?`$select=assignedLicenses" -tenantid $TenantFilter
            $CurrentSkus = @($Current.assignedLicenses.skuId)
            $RemoveLicenses = @($CurrentSkus | Where-Object { $_ -notin $AddLicenses })
            $AddLicenses = @($AddLicenses | Where-Object { $_ -notin $CurrentSkus })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API $APIName -tenant $TenantFilter -Headers $Headers -message "Failed to fetch current licenses for group $GroupName. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
            throw "Failed to fetch current licenses for group $GroupName. Error: $($ErrorMessage.NormalizedError)"
        }
    }

    if ($AddLicenses.Count -eq 0 -and $RemoveLicenses.Count -eq 0) {
        return @("No license changes required for group $GroupName.")
    }

    $AddLicensesArray = foreach ($SkuId in $AddLicenses) {
        # Graph GUIDs are lowercase, the forms post whatever casing the dropdown carried: match the key case-insensitively
        $PlanEntry = if ($DisabledPlans -is [System.Collections.IDictionary]) {
            $DisabledPlans.Keys | Where-Object { $_ -eq $SkuId } | ForEach-Object { $DisabledPlans[$_] }
        } elseif ($null -ne $DisabledPlans) {
            $DisabledPlans.PSObject.Properties | Where-Object { $_.Name -eq $SkuId } | ForEach-Object { $_.Value }
        }
        $Plans = @(
            $PlanEntry |
                Where-Object { $_ } |
                ForEach-Object { [string]($_.value ?? $_) } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        @{ disabledPlans = @($Plans); skuId = $SkuId }
    }
    $LicenseBody = @{
        addLicenses = @($AddLicensesArray)
        removeLicenses = @($RemoveLicenses)
    } | ConvertTo-Json -Compress -Depth 10

    $Results = [System.Collections.Generic.List[string]]::new()
    try {
        $Attempts = 0
        while ($true) {
            $Attempts++
            try {
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/groups/$($GroupId)/assignLicense" -tenantid $TenantFilter -body $LicenseBody -type POST
                break
            } catch {
                # A newly created group may not have replicated yet
                if ($Attempts -ge 6 -or $_.Exception.Message -notmatch 'does not exist') { throw }
                Start-Sleep -Seconds 5
            }
        }

        if ($AddLicenses.Count -gt 0) {
            $Added = foreach ($Lic in $AddLicensesArray) {
                if ($Lic.disabledPlans.Count -gt 0) { "$($Lic.skuId) ($($Lic.disabledPlans.Count) service plans disabled)" } else { $Lic.skuId }
            }
            $Message = "Assigned licenses to group $GroupName. Added: $($Added -join ', ')"
            [void]$Results.Add("$Message. It may take 2-5 minutes for changes to apply to members.")
            Write-LogMessage -API $APIName -tenant $TenantFilter -Headers $Headers -message $Message -Sev Info
        }
        if ($RemoveLicenses.Count -gt 0) {
            $Message = "Removed licenses from group $GroupName. Removed: $($RemoveLicenses -join ', ')"
            [void]$Results.Add("$Message. It may take 2-5 minutes for changes to apply to members.")
            Write-LogMessage -API $APIName -tenant $TenantFilter -Headers $Headers -message $Message -Sev Info
        }
        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -Headers $Headers -message "Failed to update licenses for group $GroupName. Error: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        throw "Failed to update licenses for group $GroupName. Error: $($ErrorMessage.NormalizedError)"
    }
}

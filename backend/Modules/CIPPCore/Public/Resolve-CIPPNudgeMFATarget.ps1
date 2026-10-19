function Resolve-CIPPNudgeMFATarget {
    <#
    .NOTES
        Permission: Graph | GET /groups | Delegated | Group.ReadBasic.All | Directory.Read.All, Directory.ReadWrite.All, Group-PreferredDataLocation.ReadWrite.All, Group.ManageProtection.All, Group.Read.All, Group.ReadWrite.All, GroupMember.Read.All
    #>
    param($Entries, $TenantFilter)
    $Resolved = [System.Collections.Generic.List[hashtable]]::new()
    $Failed = $false
    foreach ($Entry in $Entries) {
        try {
            if ($Entry -match '^(all_users|allusers|all users)$') {
                $Resolved.Add(@{ id = 'all_users'; targetType = 'group' })
            } else {
                $EscapedName = $Entry -replace "'", "''"
                $GroupFilter = [System.Uri]::EscapeDataString("startsWith(displayName,'$EscapedName')")
                $MatchedGroups = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/groups?`$select=id,displayName&`$filter=$GroupFilter" -tenantid $TenantFilter)
                if ($MatchedGroups.Count -gt 0) {
                    foreach ($Group in $MatchedGroups) { $Resolved.Add(@{ id = $Group.id; targetType = 'group' }) }
                    if ($MatchedGroups.Count -gt 1) {
                        Write-LogMessage -API 'Standards' -tenant $TenantFilter -message "NudgeMFA: Multiple groups matched '$Entry': $($MatchedGroups.displayName -join ', ')" -sev Info
                    }
                } else {
                    Write-LogMessage -API 'Standards' -tenant $TenantFilter -message "NudgeMFA: No group found matching '$Entry'" -sev Warning
                    $Failed = $true
                }
            }
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -API 'Standards' -tenant $TenantFilter -message "NudgeMFA: Failed to resolve target '$Entry'. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            $Failed = $true
        }
    }
    return [PSCustomObject]@{ Targets = $Resolved; Failed = $Failed }
}

function Find-CIPPGDAPTransitiveGroupPath {
    <#
    .NOTES
        Permission: Graph | GET /groups/{id}/members | Application | GroupMember.ReadBasic.All | Directory.Read.All, Group.Read.All, Group.ReadBasic.All, Group.ReadWrite.All, GroupMember.Read.All, GroupMember.ReadWrite.All
    #>
    param(
        [string]$UserId,
        [string]$TargetGroupId,
        [string]$TargetGroupName,
        [hashtable]$VisitedGroups = @{},
        [int]$MaxDepth = 10
    )

    # Prevent infinite loops and excessive depth
    if ($VisitedGroups.ContainsKey($TargetGroupId) -or $MaxDepth -le 0) {
        return $null
    }
    $VisitedGroups[$TargetGroupId] = $true

    try {
        # Check if user is directly in target group
        $DirectMembers = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/groups/$TargetGroupId/members?`$select=id,displayName,userPrincipalName" -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true -ErrorAction SilentlyContinue
        if ($DirectMembers.value | Where-Object { $_.id -eq $UserId }) {
            # User is directly in target group
            return @(
                @{
                    sequence        = 0
                    groupId         = $TargetGroupId
                    groupName       = $TargetGroupName
                    membershipType  = 'direct'
                }
            )
        }

        # User is not directly in target group, check nested groups
        $GroupMembers = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/groups/$TargetGroupId/members?`$select=id,displayName,@odata.type" -tenantid $env:TenantID -NoAuthCheck $true -AsApp $true -ErrorAction SilentlyContinue

        if ($GroupMembers.value) {
            foreach ($Member in $GroupMembers.value) {
                # Only check groups, not users
                if ($Member.'@odata.type' -eq '#microsoft.graph.group') {
                    $IntermediateGroupId = $Member.id
                    $IntermediateGroupName = $Member.displayName

                    # Recursively check if user is in this intermediate group
                    $SubPath = Find-CIPPGDAPTransitiveGroupPath -UserId $UserId -TargetGroupId $IntermediateGroupId -TargetGroupName $IntermediateGroupName -VisitedGroups $VisitedGroups -MaxDepth ($MaxDepth - 1)

                    if ($SubPath) {
                        # Found a path! Build the complete chain
                        $Sequence = 0
                        $Path = @(
                            # Add intermediate groups from sub-path
                            foreach ($PathItem in $SubPath) {
                                @{
                                    sequence        = $Sequence++
                                    groupId         = $PathItem.groupId
                                    groupName       = $PathItem.groupName
                                    membershipType  = $PathItem.membershipType  # Preserve membership type from sub-path
                                }
                            }

                            # Add target group at the end (intermediate group is nested in target)
                            @{
                                sequence        = $Sequence
                                groupId         = $TargetGroupId
                                groupName       = $TargetGroupName
                                membershipType  = 'nested'
                            }
                        )

                        return $Path
                    }
                }
            }
        }
    } catch {
        # If we can't check (permissions, API error), return null
        # Silently fail - errors are expected when checking group memberships
    }

    return $null
}

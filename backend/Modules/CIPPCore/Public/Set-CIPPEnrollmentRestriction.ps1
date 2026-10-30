function Set-CIPPEnrollmentRestriction {
    <#
    .SYNOPSIS
        Creates or updates an enrollment (device type) restriction, then sets its priority and
        assignment.
    .DESCRIPTION
        Writes one singlePlatformRestriction object per Graph platform type the platform needs
        (two for Android). Objects are matched by -ConfigurationIds when editing a known
        restriction, otherwise by display name and platform type; a match is patched and a
        missing type is created, so an Android restriction missing one half is completed.

        Priority (from the settings) is applied to newly created objects only, unless
        -PriorityMode Always, which also moves existing objects - used when an operator edits a
        restriction's priority by hand. Priority is relative to the tenant's other restrictions
        on the same platform, so templates only set it at creation.

        Assignment goes through Set-CIPPAssignedPolicy, the same path Intune policies use, so
        AssignTo and customGroup (names, wildcards allowed) or -GroupIds behave identically. A
        restriction with a named target owns its assignment and is replaced to exactly that set;
        'On' (do not assign) leaves the assignment as it is.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        [Parameter(Mandatory = $true)]
        $Settings,
        [string[]]$ConfigurationIds,
        [string[]]$GroupIds,
        [ValidateSet('OnCreate', 'Always')]
        [string]$PriorityMode = 'OnCreate',
        $Headers,
        $APIName = 'Set Enrollment Restriction'
    )

    $DisplayName = "$($Settings.displayName)"
    if ([string]::IsNullOrWhiteSpace($DisplayName)) { throw 'A restriction name is required.' }
    $Bodies = New-CIPPEnrollmentRestrictionBody -Settings $Settings
    $AssignTarget = Get-CIPPIntuneAssignTarget -AssignTo $Settings.AssignTo
    $BaseUri = 'https://graph.microsoft.com/beta/deviceManagement/deviceEnrollmentConfigurations'

    try {
        $Existing = @(New-GraphGetRequest -uri "$BaseUri`?`$top=999" -tenantid $TenantFilter | Where-Object { "$($_.'@odata.type')" -match 'deviceEnrollmentPlatformRestrictionConfiguration$' })

        $Created = 0
        $Updated = 0
        foreach ($PlatformType in $Bodies.Keys) {
            $Body = $Bodies[$PlatformType]
            $Match = $(if ($ConfigurationIds) {
                    $Existing | Where-Object { "$($_.id)" -in $ConfigurationIds -and "$($_.platformType)" -eq $PlatformType } | Select-Object -First 1
                } else {
                    $Existing | Where-Object { "$($_.displayName)" -eq $DisplayName -and "$($_.platformType)" -eq $PlatformType } | Select-Object -First 1
                })

            $IsNew = $null -eq $Match
            $Id = $Match.id
            if ($IsNew) {
                if ($PSCmdlet.ShouldProcess("$DisplayName ($PlatformType)", 'Create enrollment restriction')) {
                    $Id = (New-GraphPOSTRequest -uri $BaseUri -tenantid $TenantFilter -type POST -body (ConvertTo-Json -InputObject $Body -Depth 10 -Compress)).id
                    $Created++
                }
            } else {
                # The platform type is fixed when the object is created.
                $PatchBody = [ordered]@{}
                foreach ($Key in $Body.Keys) { if ($Key -ne 'platformType') { $PatchBody[$Key] = $Body[$Key] } }
                if ($PSCmdlet.ShouldProcess("$DisplayName ($PlatformType)", 'Update enrollment restriction')) {
                    $null = New-GraphPOSTRequest -uri "$BaseUri/$Id" -tenantid $TenantFilter -type PATCH -body (ConvertTo-Json -InputObject $PatchBody -Depth 10 -Compress)
                    $Updated++
                }
            }
            if (-not $Id) { continue }

            if ($null -ne $Settings.priority -and ($IsNew -or ($PriorityMode -eq 'Always' -and "$($Match.priority)" -ne "$($Settings.priority)"))) {
                if ($PSCmdlet.ShouldProcess("$DisplayName ($PlatformType)", "Set priority $($Settings.priority)")) {
                    $null = New-GraphPOSTRequest -uri "$BaseUri/$Id/setPriority" -tenantid $TenantFilter -type POST -body (@{ priority = [int]$Settings.priority } | ConvertTo-Json -Compress)
                }
            }
            if ($AssignTarget.Managed) {
                $AssignParams = @{
                    GroupName      = $(if ($AssignTarget.AssignTo -eq 'customGroup') { $Settings.customGroup } else { $AssignTarget.AssignTo })
                    PolicyId       = $Id
                    Type           = 'deviceEnrollmentConfigurations'
                    TenantFilter   = $TenantFilter
                    AssignmentMode = 'replace'
                    Headers        = $Headers
                    APIName        = $APIName
                }
                # '@($null).Count' is 1, so test the value before counting it.
                if ($AssignTarget.AssignTo -eq 'customGroup' -and $GroupIds -and @($GroupIds).Count -gt 0) { $AssignParams.GroupIds = @($GroupIds) }
                $null = Set-CIPPAssignedPolicy @AssignParams
            }
        }

        $Verb = $(if ($Created -gt 0 -and $Updated -eq 0) { 'Created' } else { 'Updated' })
        $Result = "$Verb $($Settings.platform) enrollment restriction '$DisplayName' for $TenantFilter"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Info'
        $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to set enrollment restriction '$DisplayName' for $($TenantFilter): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}

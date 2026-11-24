function Invoke-ListDeletedItems {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.Read
    .DESCRIPTION
        Lists soft-deleted directory objects in Entra ID, including users, groups, applications, service principals, and administrative units.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter

    $Types = @('administrativeUnit', 'application', 'externalUserProfile', 'pendingExternalUserProfile', 'user', 'group', 'servicePrincipal', 'certificateBasedAuthPki', 'certificateAuthorityDetail')
    $Requests = foreach ($Type in $Types) {
        [PSCustomObject]@{
            id     = $Type
            url    = "directory/deletedItems/microsoft.graph.$($Type)"
            method = 'GET'
        }
    }

    $BulkResults = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter

    $Failed = [System.Collections.Generic.List[string]]::new()
    $GraphRequest = foreach ($Type in $Types) {
        # pretty format the type name
        $FormattedType = (Get-Culture).TextInfo.ToTitleCase(($Type -creplace '([A-Z])', ' $1').Trim())

        $Result = $BulkResults | Where-Object { $_.id -eq $Type }
        if ($Result.status -eq 200) {
            $Result.body.value | ForEach-Object {
                $_ | Add-Member -NotePropertyName 'TargetType' -NotePropertyValue $FormattedType
                $_
            }
        } else {
            $Failed.Add("$($FormattedType): $($Result.body.error.message ?? $Result.status ?? 'no response')")
        }
    }

    # Some types failing still returns the rest (207); all failing is an error, not an empty list
    $StatusCode = Get-CippBulkStatusCode -Total $Types.Count -Failed $Failed.Count
    if ($Failed.Count -gt 0) {
        Write-LogMessage -API 'ListDeletedItems' -tenant $TenantFilter -message "Could not list deleted $($Failed -join '; ')" -sev Warning
    }
    if ($Failed.Count -eq $Types.Count) { $GraphRequest = "Could not list deleted items: $($Failed -join '; ')" }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}

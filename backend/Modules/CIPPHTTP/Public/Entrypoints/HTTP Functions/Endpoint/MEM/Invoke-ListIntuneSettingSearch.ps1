function Invoke-ListIntuneSettingSearch {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Searches cached Intune policies (settings catalog, custom OMA-URI and property-based policies) for settings whose name or id contains the search text, case-insensitively. Returns one row per setting with the policies that configure it, sorted by setting name. PolicyTypes on each setting is the distinct policy types of its policies, sorted and comma separated. Reads the reporting database only. Works for a single tenant only: AllTenants and tenant groups (a 'group:' tenantFilter) return 400. A search shorter than 3 characters returns no rows. At most 500 settings are returned; Metadata.Truncated is true when more matched. When truncated, the rows are the first 500 matching settings found in the cache, sorted by setting name, not the alphabetically first 500 of all matches. DeviceCount on each setting and on each of its Policies is the number of distinct devices in the cached device statuses or settings catalog device reports, and null when none of the policies has cached device data, such as policy types without a device report or policies not synced yet.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $MinSearchLength = 3
    $MaxResults = 500

    $TenantFilter = $Request.Query.TenantFilter
    $Search = "$($Request.Query.search)".Trim()

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter is required.' }
            })
    }

    if (-not (Test-CIPPSingleTenantFilter -TenantFilter $TenantFilter)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Setting search works on one tenant at a time. Select a single tenant.' }
            })
    }

    if ($Search.Length -lt $MinSearchLength) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{
                    Results  = @()
                    Metadata = @{ Truncated = $false }
                }
            })
    }

    try {
        # The search keeps the first MaxResults + 1 settings it finds, so one row past the cap shows that more matched.
        $Results = @(Get-CIPPIntuneSettingSearch -TenantFilter $TenantFilter -Search $Search -MaxResults $MaxResults -ErrorAction Stop)
        $Truncated = $Results.Count -gt $MaxResults
        $Results = @($Results | Select-Object -First $MaxResults)
        try {
            Add-CIPPIntuneSettingDeviceCount -TenantFilter $TenantFilter -Results $Results -ErrorAction Stop
        } catch {
            Write-LogMessage -API 'IntuneSettingSearch' -tenant $TenantFilter -message "Failed to count devices for Intune setting search: $($_.Exception.Message)" -sev Warning -LogData (Get-CippException -Exception $_)
        }
        $Body = @{
            Results  = $Results
            Metadata = @{ Truncated = $Truncated }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ Results = Get-NormalizedError -Message $_.Exception.Message }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

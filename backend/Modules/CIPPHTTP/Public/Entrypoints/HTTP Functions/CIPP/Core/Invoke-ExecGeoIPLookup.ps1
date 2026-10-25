Function Invoke-ExecGeoIPLookup {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Resolves a single IP address to its geographic location using CIPP's bundled GeoIP database. An address with a
        port, as audit logs record it ('203.0.113.10:13892' or '[2001:db8::1]:443'), is looked up without the port.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # The IP address to locate; a port and IPv6 brackets are removed.
    $IP = [string]($Request.Query.IP ?? $Request.Body.IP)
    $IP = ([regex]'^(?<IP>(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+))(?::\d+)?$').Replace($IP.Trim(), '$1') -replace '[\[\]]', ''

    if (-not $IP) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = Get-NormalizedError -Message 'IP address is required'
            })
    }
    if ($IP -notmatch '^(\d{1,3}(\.\d{1,3}){3}|[0-9a-fA-F:]+)$') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = "Not an IP address: $IP"
            })
    }

    try {
        $LocationInfo = Get-CIPPGeoIPLocation -IP $IP
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $LocationInfo = $_.Exception.Message
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $LocationInfo
        })

}

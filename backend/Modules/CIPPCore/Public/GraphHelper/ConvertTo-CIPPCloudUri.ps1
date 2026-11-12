function ConvertTo-CIPPCloudUri {
    <#
    .SYNOPSIS
        Points a request URI at the right host for a tenant's cloud.
    .DESCRIPTION
        Commercial: the URI is returned exactly as given. Government (USGovHigh, USGovDoD): the URI
        is parsed with [uri] and its host replaced by Resolve-CIPPCloudHost - for example
        https://graph.microsoft.com/beta/users becomes https://graph.microsoft.us/beta/users - with
        the path, query and fragment kept byte for byte. A host of the tenant's own cloud (such as an
        @odata.nextLink Graph returned) is kept. Anything else throws before a request is made:
        a host with no government equivalent, a relative or non-https URI, user info or a port.
    .PARAMETER Uri
        Absolute https URI.
    .PARAMETER CloudEnvironment
        Commercial, USGovHigh or USGovDoD (exact case).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Uri,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$CloudEnvironment
    )

    $Endpoint = Get-CIPPCloudEndpoint -CloudEnvironment $CloudEnvironment
    if (-not $Endpoint.IsGovernment) { return $Uri }

    $Parsed = $null
    if (-not [System.Uri]::TryCreate($Uri, [System.UriKind]::Absolute, [ref]$Parsed) -or $Parsed.Scheme -ne 'https') {
        throw "Only absolute https URIs can be sent for a government tenant ($($Endpoint.CloudEnvironment))."
    }
    # The text between '://' and the path must be the bare host (optionally :443), so that what
    # is replaced below is exactly what [uri] parsed - no user info, backslashes or other ports.
    $AuthorityStart = $Uri.IndexOf('://') + 3
    $AuthorityEnd = $Uri.IndexOfAny([char[]]@('/', '?', '#'), $AuthorityStart)
    if ($AuthorityEnd -lt 0) { $AuthorityEnd = $Uri.Length }
    $Authority = $Uri.Substring($AuthorityStart, $AuthorityEnd - $AuthorityStart)
    if (-not ($Authority -ieq $Parsed.Host -or $Authority -ieq "$($Parsed.Host):443")) {
        throw "The URI's host could not be read unambiguously for a government tenant ($($Endpoint.CloudEnvironment))."
    }

    $TargetHost = Resolve-CIPPCloudHost -HostName $Parsed.Host -CloudEnvironment $Endpoint.CloudEnvironment
    $Result = 'https://' + $TargetHost + $Uri.Substring($AuthorityEnd)
    # Belt and braces: the URI we hand back must parse to the host we decided on.
    $Check = $null
    if (-not [System.Uri]::TryCreate($Result, [System.UriKind]::Absolute, [ref]$Check) -or $Check.Host -ne $TargetHost.ToLowerInvariant()) {
        throw "Could not route the URI for a government tenant ($($Endpoint.CloudEnvironment))."
    }
    return $Result
}

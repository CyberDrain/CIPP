function ConvertTo-CIPPCloudUri {
    <#
    .SYNOPSIS
        Points a request URI at the right host for a tenant's cloud.
    .DESCRIPTION
        Commercial URIs are returned as given. For a government cloud the host is replaced by
        Resolve-CIPPCloudHost; anything it cannot map, and non-https or relative URIs, throw.
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
    # Bare host only (optionally :443), so the replace below matches what [uri] parsed.
    $AuthorityStart = $Uri.IndexOf('://') + 3
    $AuthorityEnd = $Uri.IndexOfAny([char[]]@('/', '?', '#'), $AuthorityStart)
    if ($AuthorityEnd -lt 0) { $AuthorityEnd = $Uri.Length }
    $Authority = $Uri.Substring($AuthorityStart, $AuthorityEnd - $AuthorityStart)
    if (-not ($Authority -ieq $Parsed.Host -or $Authority -ieq "$($Parsed.Host):443")) {
        throw "The URI's host could not be read unambiguously for a government tenant ($($Endpoint.CloudEnvironment))."
    }

    $TargetHost = Resolve-CIPPCloudHost -HostName $Parsed.Host -CloudEnvironment $Endpoint.CloudEnvironment
    $Result = 'https://' + $TargetHost + $Uri.Substring($AuthorityEnd)
    $Check = $null
    if (-not [System.Uri]::TryCreate($Result, [System.UriKind]::Absolute, [ref]$Check) -or $Check.Host -ne $TargetHost.ToLowerInvariant()) {
        throw "Could not route the URI for a government tenant ($($Endpoint.CloudEnvironment))."
    }
    return $Result
}

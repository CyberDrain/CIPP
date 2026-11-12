function ConvertTo-CIPPCloudScope {
    <#
    .SYNOPSIS
        Translates an OAuth scope string from commercial resources to a tenant's cloud.
    .DESCRIPTION
        Hosts are mapped by Resolve-CIPPCloudHost; OpenID scopes pass through. A resource with no
        government host throws for a government tenant.
    .PARAMETER Scope
        A single scope or a space-separated list.
    .PARAMETER CloudEnvironment
        Commercial, USGovHigh or USGovDoD (exact case).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Scope,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$CloudEnvironment
    )

    $Endpoint = Get-CIPPCloudEndpoint -CloudEnvironment $CloudEnvironment
    if (-not $Endpoint.IsGovernment) { return $Scope }

    $PassThrough = @('openid', 'profile', 'offline_access', 'email')

    $Translated = foreach ($Item in ($Scope -split '\s+' | Where-Object { $_ })) {
        if ($PassThrough -contains $Item) { $Item; continue }
        $Parsed = $null
        if (-not [System.Uri]::TryCreate($Item, [System.UriKind]::Absolute, [ref]$Parsed) -or $Parsed.Scheme -ne 'https') {
            # Don't echo the scope in the error.
            throw "Tokens for this resource are not supported for government tenants ($CloudEnvironment); only resources with a documented government host are."
        }
        ConvertTo-CIPPCloudUri -Uri $Item -CloudEnvironment $Endpoint.CloudEnvironment
    }
    if (-not $Translated) { throw 'No scope to request.' }
    return ($Translated -join ' ')
}

function ConvertTo-CIPPCloudScope {
    <#
    .SYNOPSIS
        Translates an OAuth scope string from commercial resources to a tenant's cloud.
    .DESCRIPTION
        Callers ask Get-GraphToken for commercial scopes (https://graph.microsoft.com/.default,
        https://outlook.office365.com/.default, ...). For a government tenant the host of each
        scope is mapped by Resolve-CIPPCloudHost, the same decision the request helpers use for URIs
        (redanthrax/CIPP#3): Graph, Exchange, the Office 365 Management API and Defender for Endpoint
        move to that cloud's host, a scope already on that cloud's host or on its SharePoint suffix
        is kept, and OpenID scopes (openid, profile, offline_access, email) pass through.

        Any other resource - Partner Center, Teams admin, Security & Compliance, a GUID resource,
        commercial SharePoint - throws for a government tenant instead of being sent as is: a
        commercial resource cannot be issued by a government authority. Commercial scopes are
        returned unchanged.
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
            # A GUID resource (e.g. 48ac35b8-.../.default) names no cloud. Name nothing from the scope.
            throw "Tokens for this resource are not supported for government tenants ($CloudEnvironment); only resources with a documented government host are (see redanthrax/CIPP#3)."
        }
        # Throws, naming only the host, for a resource with no government host.
        ConvertTo-CIPPCloudUri -Uri $Item -CloudEnvironment $Endpoint.CloudEnvironment
    }
    if (-not $Translated) { throw 'No scope to request.' }
    return ($Translated -join ' ')
}

function Get-CIPPClientCredentialToken {
    <#
    .SYNOPSIS
        Returns an access token from the client credentials grant, reusing it until shortly before it expires.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [string]$ClientSecret,

        [Parameter(Mandatory = $true)]
        [string]$Scope
    )

    if ($TenantId -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]{0,252}$') {
        throw [System.ArgumentException]::new("'$TenantId' is not a valid tenant id or domain.")
    }

    $SecretHash = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($ClientSecret)))
    $CacheKey = "$TenantId|$ClientId|$Scope|$SecretHash"
    $Now = [datetime]::UtcNow
    $script:CIPPClientCredentialTokenCache ??= @{}
    $Cached = $script:CIPPClientCredentialTokenCache[$CacheKey]
    if ($Cached -and $Cached.Expires -gt $Now) { return $Cached.Token }

    $Body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $Scope
        grant_type    = 'client_credentials'
    }
    $Response = Invoke-CIPPRestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $Body -ContentType 'application/x-www-form-urlencoded' -SkipHttpErrorCheck
    if (-not $Response.access_token) {
        $Reason = if ($Response.error_description) { $Response.error_description -replace '\s*Trace ID:[\s\S]*$' } elseif ($Response.error) { $Response.error } else { 'no token was returned' }
        throw "Could not sign in as application $ClientId in tenant $($TenantId): $Reason"
    }

    foreach ($Key in @($script:CIPPClientCredentialTokenCache.PSBase.Keys)) {
        if ($script:CIPPClientCredentialTokenCache[$Key].Expires -le $Now) { $script:CIPPClientCredentialTokenCache.Remove($Key) }
    }
    if ($script:CIPPClientCredentialTokenCache.PSBase.Count -ge 50) { $script:CIPPClientCredentialTokenCache.Clear() }

    $Lifetime = [Math]::Max(([int]$Response.expires_in) - 300, 0)
    $script:CIPPClientCredentialTokenCache[$CacheKey] = @{ Token = $Response.access_token; Expires = $Now.AddSeconds($Lifetime) }
    return $Response.access_token
}

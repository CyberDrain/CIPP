function Get-CIPPAccessTokenCloudEnvironment {
    <#
    .SYNOPSIS
        Works out which Microsoft cloud a Graph access token belongs to from its claims.
    .DESCRIPTION
        No signature check: Graph validates the token. Only the aud claim separates GCC High from DoD.
        Throws on any contradiction or unknown value, without echoing claim values.
    .PARAMETER AccessToken
        The raw access token (header.payload.signature).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$AccessToken
    )

    $Parts = $AccessToken -split '\.'
    if ($Parts.Count -ne 3 -or [string]::IsNullOrEmpty($Parts[1])) {
        throw 'The access token is not a JWT.'
    }
    try {
        $Payload = $Parts[1].Replace('-', '+').Replace('_', '/')
        switch ($Payload.Length % 4) {
            2 { $Payload += '==' }
            3 { $Payload += '=' }
            1 { throw 'bad length' }
        }
        $Json = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Payload))
        $Claims = $Json | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw 'The access token payload could not be decoded.'
    }

    # Ordinal lookups; only the audience tolerates a trailing slash.
    $AudienceMap = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $AudienceMap['https://graph.microsoft.com'] = 'Commercial'
    $AudienceMap['https://graph.microsoft.us'] = 'USGovHigh'
    $AudienceMap['https://dod-graph.microsoft.us'] = 'USGovDoD'
    $AudienceMap['00000003-0000-0000-c000-000000000000'] = ''

    $IssuerFamilyMap = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $IssuerFamilyMap['login.microsoftonline.com'] = 'Commercial'
    $IssuerFamilyMap['login.microsoftonline.us'] = 'Government'
    $IssuerFamilyMap['sts.windows.net'] = 'Any'

    $Audience = if ($Claims.aud -is [string]) { $Claims.aud.TrimEnd('/') } else { '' }
    $Cloud = $null
    if (-not $AudienceMap.TryGetValue($Audience, [ref]$Cloud)) {
        throw 'The access token is not for a known Microsoft Graph cloud.'
    }

    $IssuerUri = $null
    if (-not ($Claims.iss -is [string]) -or -not [System.Uri]::TryCreate($Claims.iss, [System.UriKind]::Absolute, [ref]$IssuerUri) -or $IssuerUri.Scheme -ne 'https') {
        throw 'The access token has no usable issuer.'
    }
    $IssuerFamily = $null
    if (-not $IssuerFamilyMap.TryGetValue($IssuerUri.Host, [ref]$IssuerFamily)) {
        throw 'The access token was issued by an unknown authority.'
    }
    $Cloud = if ($Cloud) { $Cloud } else { $null }
    $AudienceFamily = if (-not $Cloud) { $null } elseif ($Cloud -eq 'Commercial') { 'Commercial' } else { 'Government' }
    if ($IssuerFamily -ne 'Any' -and $AudienceFamily -and $IssuerFamily -ne $AudienceFamily) {
        throw 'The access token issuer and audience belong to different clouds.'
    }
    $Family = if ($AudienceFamily) { $AudienceFamily } elseif ($IssuerFamily -ne 'Any') { $IssuerFamily } else { $null }
    return [pscustomobject]@{
        CloudEnvironment = $Cloud
        Family           = $Family
    }
}

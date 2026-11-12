function Get-CIPPAccessTokenCloudEnvironment {
    <#
    .SYNOPSIS
        Works out which Microsoft cloud a Graph access token belongs to from its claims.
    .DESCRIPTION
        Decodes the JWT payload (no signature check: the token is only used to call Graph, which
        validates it) and classifies it with two fixed lookups:

          aud (the Graph resource the token is for):
              https://graph.microsoft.com     Commercial
              https://graph.microsoft.us      USGovHigh
              https://dod-graph.microsoft.us  USGovDoD
              00000003-0000-0000-c000-000000000000 (Graph's app id) - names no cloud
          iss host (the authority that issued it):
              login.microsoftonline.com       commercial family (v2 tokens)
              login.microsoftonline.us        government family (v2 tokens)
              sts.windows.net                 no family (v1 tokens, which Graph issues by default)

        The audience is the only claim that separates GCC High from DoD - both sign in at
        login.microsoftonline.us. Returns the cloud when the audience names one, and the family
        (Commercial or Government) when either claim decides it; both can be $null for a v1 token
        with the bare Graph app id audience. An issuer family that contradicts the audience,
        anything that does not decode, an unknown audience or an unknown issuer host throws.
        Callers treat a throw as "reject the token". No claim value is echoed in the error.
    .PARAMETER AccessToken
        The raw access token (header.payload.signature).
    .OUTPUTS
        PSCustomObject with CloudEnvironment (Commercial, USGovHigh, USGovDoD or $null) and Family
        (Commercial, Government or $null).
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

    # Exact (ordinal) lookups. A trailing slash is tolerated on the audience only.
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

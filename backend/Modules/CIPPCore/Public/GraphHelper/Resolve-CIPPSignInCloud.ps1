function Resolve-CIPPSignInCloud {
    <#
    .SYNOPSIS
        Checks that a direct-tenant sign-in token belongs to the cloud the user picked (redanthrax/CIPP#2).
    .DESCRIPTION
        The consent flow sends the cloud the user picked (absent means Commercial, as before #2) and the
        access token it got. The token's own claims (Get-CIPPAccessTokenCloudEnvironment) are the
        stronger evidence: a token naming another cloud, or another cloud family, is refused. The
        claims are not verified here - they only choose among the fixed entries of
        Get-CIPPCloudEndpoint, and Microsoft validates the token when it is used.

        Throws for an unknown or non-string cloud, a token that does not decode or a disagreement.
        No claim value is echoed in an error.
    .PARAMETER CloudEnvironment
        The cloud from the request body: $null, Commercial, USGovHigh or USGovDoD (exact case).
    .PARAMETER AccessToken
        The access token from the sign-in.
    .OUTPUTS
        The Get-CIPPCloudEndpoint entry of the sign-in's cloud.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $CloudEnvironment,
        [AllowEmptyString()]
        [AllowNull()]
        [string]$AccessToken
    )

    $Requested = if ($null -eq $CloudEnvironment) { 'Commercial' } else { $CloudEnvironment }
    if ($Requested -isnot [string]) { throw 'Invalid cloudEnvironment.' }
    $Endpoint = Get-CIPPCloudEndpoint -CloudEnvironment $Requested
    $TokenInfo = Get-CIPPAccessTokenCloudEnvironment -AccessToken ([string]$AccessToken)
    $RequestedFamily = if ($Endpoint.IsGovernment) { 'Government' } else { 'Commercial' }
    if ($TokenInfo.CloudEnvironment -and $TokenInfo.CloudEnvironment -cne $Endpoint.CloudEnvironment) {
        throw "The sign-in token is for $($TokenInfo.CloudEnvironment), not the selected $($Endpoint.CloudEnvironment)."
    }
    if ($TokenInfo.Family -and $TokenInfo.Family -ne $RequestedFamily) {
        throw "The sign-in token is from the $($TokenInfo.Family) cloud, not the selected $($Endpoint.CloudEnvironment)."
    }
    return $Endpoint
}

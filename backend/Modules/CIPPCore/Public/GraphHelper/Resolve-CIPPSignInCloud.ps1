function Resolve-CIPPSignInCloud {
    <#
    .SYNOPSIS
        Checks that a direct-tenant sign-in token belongs to the cloud the user picked.
    .DESCRIPTION
        Claims are not verified; they only pick a fixed Get-CIPPCloudEndpoint entry. No claim value is echoed.
    .PARAMETER CloudEnvironment
        The cloud from the request body: $null, Commercial, USGovHigh or USGovDoD (exact case).
    .PARAMETER AccessToken
        The access token from the sign-in.
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

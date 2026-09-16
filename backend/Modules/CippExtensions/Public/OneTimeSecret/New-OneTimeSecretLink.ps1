function New-OneTimeSecretLink {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Payload,
        $Configuration,
        [switch]$ThrowOnError
    )

    $FailureMessage = 'Could not read the One-Time Secret configuration.'
    try {
        if (-not $Configuration) {
            $Table = Get-CIPPTable -TableName Extensionsconfig
            $ConfigEntity = Get-CIPPAzDataTableEntity @Table
            if (-not $ConfigEntity.config) { return $false }
            $Configuration = ($ConfigEntity.config | ConvertFrom-Json -ErrorAction Stop).OneTimeSecret
        }
        if ($Configuration.Enabled -ne $true) { return $false }

        $FailureMessage = 'One-Time Secret requires an HTTPS base URL without credentials, a query string, or a fragment.'
        $BaseUri = $null
        if (-not [uri]::TryCreate([string]$Configuration.BaseUrl, [UriKind]::Absolute, [ref]$BaseUri) -or
            $BaseUri.Scheme -ne 'https' -or $BaseUri.UserInfo -or $BaseUri.Query -or $BaseUri.Fragment) {
            throw $FailureMessage
        }
        $BaseUrl = $BaseUri.AbsoluteUri.TrimEnd('/')

        $FailureMessage = 'Set the One-Time Secret account email and save its API key before creating a link.'
        if ([string]::IsNullOrWhiteSpace($Configuration.EmailAddress)) { throw $FailureMessage }
        $ApiKey = Get-ExtensionAPIKey -Extension 'OneTimeSecret' -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw $FailureMessage }

        $FailureMessage = 'One-Time Secret expiration must be a whole number from 1 to 168 hours.'
        $ExpireAfterHours = 24
        if (-not [string]::IsNullOrWhiteSpace([string]$Configuration.ExpireAfterHours)) {
            if (-not [int]::TryParse([string]$Configuration.ExpireAfterHours, [ref]$ExpireAfterHours) -or
                $ExpireAfterHours -lt 1 -or $ExpireAfterHours -gt 168) {
                throw $FailureMessage
            }
        }
        $FailureMessage = 'Cannot create a One-Time Secret link for an empty password.'
        if ([string]::IsNullOrEmpty($Payload)) { throw $FailureMessage }

        $Secret = @{
            kind         = 'conceal'
            secret       = $Payload
            share_domain = ''
            ttl          = $ExpireAfterHours * 3600
        }
        if (-not [string]::IsNullOrEmpty($Configuration.DefaultPassphrase)) {
            $Secret.passphrase = $Configuration.DefaultPassphrase
        }
        $Credentials = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$($Configuration.EmailAddress):$ApiKey"))
        $Headers = @{ Authorization = "Basic $Credentials"; Accept = 'application/json' }

        if ($PSCmdlet.ShouldProcess($BaseUrl, 'Create a One-Time Secret link')) {
            # Never log the response or raw exception: either can echo the password or credentials.
            $FailureMessage = 'One-Time Secret could not create a link. Check the saved URL, credentials, and service availability.'
            try {
                $Response = Invoke-RestMethod -Uri "$BaseUrl/api/v2/secret/conceal" -Method Post -Headers $Headers -Body (@{ secret = $Secret } | ConvertTo-Json -Compress) -ContentType 'application/json; charset=utf-8' -TimeoutSec 30 -MaximumRedirection 0 -ErrorAction Stop
            } catch {
                if ($_.Exception.Response.StatusCode) {
                    $FailureMessage = "One-Time Secret returned HTTP $([int]$_.Exception.Response.StatusCode). Check the saved URL, credentials, and expiration against your account limits."
                }
                throw $FailureMessage
            }

            $FailureMessage = 'One-Time Secret did not return a valid secret identifier.'
            $SecretKey = $Response.record.secret.identifier
            if (-not $SecretKey) { $SecretKey = $Response.record.secret.key }
            if ($Response.success -eq $false -or $SecretKey -isnot [string] -or $SecretKey -notmatch '^[a-zA-Z0-9_-]+$') {
                throw $FailureMessage
            }
            return "$BaseUrl/secret/$SecretKey"
        }
        return $false
    } catch {
        Write-LogMessage -API OneTimeSecret -Message $FailureMessage -Sev 'Error'
        if ($ThrowOnError) { throw $FailureMessage }
        return $false
    }
}

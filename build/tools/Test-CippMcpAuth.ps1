#Requires -Version 7.4
<#
.SYNOPSIS
    Walks the MCP OAuth flow against a CIPP instance the way a real connector does, step by step,
    and reports where it breaks.

.DESCRIPTION
    Public mode signs in like Claude / ChatGPT / CLI clients: auth code + PKCE, no secret, loopback
    redirect (http://127.0.0.1:<port>, already registered on every MCP client). Confidential mode
    signs in like Copilot Studio: auth code + client secret against a Web-platform redirect, so the
    redirect URI has to be added to the client as a custom Web redirect first.

    Steps: unauthenticated 401 + challenge -> protected-resource and authorization-server metadata
    -> (optional DCR) -> browser sign-in -> code exchange -> token claims -> MCP initialize,
    notifications/initialized, tools/list, tools/call ListTenants -> refresh_token grant -> tools/list
    with the refreshed token.

.PARAMETER Mode
    Public, Confidential, or Both (both flows in turn against the same ClientId).
.PARAMETER ClientId
    The MCP-enabled API client's application id. Omit in Public mode to take it from DCR.
.PARAMETER ClientSecret
    Required for Confidential. Falls back to $env:CIPP_MCP_CLIENT_SECRET.
.PARAMETER ConfidentialRedirectUri
    Must be registered on the client as a Web redirect. Not /callback: the built-in public
    http://localhost/callback matches any localhost port, so Entra would treat the client as public.
.PARAMETER UseResourceIndicator
    Send the RFC 8707 resource parameter (the MCP server URL) on authorize and refresh, as Claude
    does. Reproduces the AADSTS90009 refresh failure when the client is also the resource.
.PARAMETER NoPkce
    Confidential only: skip PKCE.
.PARAMETER UserAgent
    Sent on every request. EasyAuth answers a browser-like agent (anything containing 'Mozilla') with
    a 302 to the portal login instead of the MCP 401 challenge, so pass one to test that case.

.EXAMPLE
    ./build/tools/Test-CippMcpAuth.ps1 -Mode Public -ClientId <appId>
.EXAMPLE
    ./build/tools/Test-CippMcpAuth.ps1 -Mode Confidential -ClientId <appId> -ClientSecret <secret>
.EXAMPLE
    ./build/tools/Test-CippMcpAuth.ps1 -Mode Both -ClientId <appId> -ClientSecret <secret>
#>
[CmdletBinding()]
param(
    [ValidateSet('Public', 'Confidential', 'Both')][string]$Mode = 'Public',
    [string]$BaseUrl = 'https://dev.cipp.app',
    [string]$ClientId,
    [string]$ClientSecret = $env:CIPP_MCP_CLIENT_SECRET,
    [string]$ConfidentialRedirectUri = 'http://localhost:8400/confidential',
    [switch]$UseResourceIndicator,
    [switch]$NoPkce,
    [int]$SignInTimeoutSec = 300,
    [string]$UserAgent = 'Test-CippMcpAuth/1.0'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web
$PSDefaultParameterValues['Invoke-WebRequest:UserAgent'] = $UserAgent
$PSDefaultParameterValues['Invoke-RestMethod:UserAgent'] = $UserAgent
$McpUrl = "$($BaseUrl.TrimEnd('/'))/api/ExecMcp"

function Write-Step([string]$Name, [bool]$Ok, [string]$Detail) {
    $Mark = $Ok ? '[PASS]' : '[FAIL]'
    Write-Host "$Mark $Name" -ForegroundColor ($Ok ? 'Green' : 'Red')
    if ($Detail) { Write-Host "       $($Detail -replace "`n", "`n       ")" }
    if (-not $Ok) { throw "Stopped at: $Name" }
}

function ConvertFrom-Base64Url([string]$Value) {
    $Value = $Value.Replace('-', '+').Replace('_', '/')
    $Value = $Value.PadRight($Value.Length + (4 - $Value.Length % 4) % 4, '=')
    [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}

function ConvertTo-Base64Url([byte[]]$Bytes) {
    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Wait-OAuthCallback([uri]$RedirectUri, [string]$AuthorizeUrl) {
    $Addresses = $RedirectUri.Host -eq 'localhost' ? @([IPAddress]::Loopback, [IPAddress]::IPv6Loopback) : @([IPAddress]::Parse($RedirectUri.Host))
    $Listeners = foreach ($Address in $Addresses) {
        $Listener = [System.Net.Sockets.TcpListener]::new($Address, $RedirectUri.Port)
        $Listener.Start()
        $Listener
    }
    try {
        Start-Process $AuthorizeUrl
        Write-Host "       Browser opened; waiting up to $SignInTimeoutSec s for the redirect to $RedirectUri"
        $Deadline = [DateTime]::UtcNow.AddSeconds($SignInTimeoutSec)
        while ([DateTime]::UtcNow -lt $Deadline) {
            foreach ($Listener in $Listeners) {
                if (-not $Listener.Pending()) { continue }
                $Client = $Listener.AcceptTcpClient()
                try {
                    $Stream = $Client.GetStream()
                    $RequestLine = [System.IO.StreamReader]::new($Stream).ReadLine()
                    $Target = ($RequestLine -split ' ')[1]
                    if ($Target -notmatch '[?&](code|error)=') { continue }
                    $Html = '<html><body style="font-family:sans-serif">Sign-in captured. You can close this tab.</body></html>'
                    $Bytes = [System.Text.Encoding]::UTF8.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: text/html`r`nContent-Length: $([System.Text.Encoding]::UTF8.GetByteCount($Html))`r`nConnection: close`r`n`r`n$Html")
                    $Stream.Write($Bytes, 0, $Bytes.Length)
                    $Query = [System.Web.HttpUtility]::ParseQueryString(([uri]"http://x$Target").Query)
                    $Result = @{}
                    foreach ($Key in $Query.AllKeys) { $Result[$Key] = $Query[$Key] }
                    return $Result
                } finally { $Client.Dispose() }
            }
            Start-Sleep -Milliseconds 200
        }
        throw 'Timed out waiting for the sign-in redirect.'
    } finally {
        foreach ($Listener in $Listeners) { $Listener.Stop() }
    }
}

function Invoke-TokenRequest([string]$TokenEndpoint, [hashtable]$Body) {
    $Response = Invoke-WebRequest -Uri $TokenEndpoint -Method Post -Body $Body -ContentType 'application/x-www-form-urlencoded' -SkipHttpErrorCheck
    [PSCustomObject]@{ Status = [int]$Response.StatusCode; Json = ($Response.Content | ConvertFrom-Json) }
}

function Get-TokenSummary([string]$AccessToken) {
    $Claims = ConvertFrom-Base64Url ($AccessToken -split '\.')[1] | ConvertFrom-Json
    $Summary = [ordered]@{
        aud   = $Claims.aud
        azp   = $Claims.azp ?? $Claims.appid
        scp   = $Claims.scp
        roles = $Claims.roles -join ' '
        upn   = $Claims.upn ?? $Claims.preferred_username
        tid   = $Claims.tid
        ver   = $Claims.ver
        exp   = [DateTimeOffset]::FromUnixTimeSeconds($Claims.exp).UtcDateTime.ToString('u')
    }
    $Summary.GetEnumerator() | Where-Object Value | ForEach-Object { "$($_.Key)=$($_.Value)" } | Join-String -Separator "`n"
}

$script:RpcId = 0
function Invoke-Mcp([string]$AccessToken, [string]$Method, $Params, [switch]$Notification) {
    $Message = [ordered]@{ jsonrpc = '2.0'; method = $Method }
    if (-not $Notification) { $Message.id = ++$script:RpcId }
    if ($null -ne $Params) { $Message.params = $Params }
    $Headers = @{
        Authorization          = "Bearer $AccessToken"
        Accept                 = 'application/json, text/event-stream'
        'MCP-Protocol-Version' = '2025-06-18'
    }
    $Response = Invoke-WebRequest -Uri $McpUrl -Method Post -Headers $Headers -ContentType 'application/json' -Body ($Message | ConvertTo-Json -Depth 10 -Compress) -SkipHttpErrorCheck
    $Json = $Response.Content -and ($Response.Content | Test-Json -ErrorAction Ignore) ? ($Response.Content | ConvertFrom-Json) : $null
    [PSCustomObject]@{ Status = [int]$Response.StatusCode; Json = $Json; Raw = "$($Response.Content)" }
}

function Test-McpSession([string]$AccessToken, [string]$Label) {
    $Init = Invoke-Mcp $AccessToken 'initialize' @{ protocolVersion = '2025-06-18'; capabilities = @{}; clientInfo = @{ name = 'Test-CippMcpAuth'; version = '1.0' } }
    Write-Step "$Label initialize" ($Init.Status -eq 200 -and $Init.Json.result) "HTTP $($Init.Status) $($Init.Json.result ? ($Init.Json.result.serverInfo | ConvertTo-Json -Compress) : $Init.Raw)"

    $Initialized = Invoke-Mcp $AccessToken 'notifications/initialized' -Notification
    Write-Step "$Label notifications/initialized" ($Initialized.Status -in 200, 202, 204) "HTTP $($Initialized.Status)"

    $List = Invoke-Mcp $AccessToken 'tools/list' @{}
    $Tools = @($List.Json.result.tools.name)
    Write-Step "$Label tools/list" ($List.Status -eq 200 -and $Tools.Count -gt 0) "HTTP $($List.Status) $($Tools.Count) tools: $($Tools -join ', ')$(if (-not $Tools) { "`n$($List.Raw)" })"

    $Call = Invoke-Mcp $AccessToken 'tools/call' @{ name = 'ListTenants'; arguments = @{} }
    $Ok = $Call.Status -eq 200 -and $Call.Json.result -and -not $Call.Json.result.isError
    $Text = "$(@($Call.Json.result.content)[0].text ?? $Call.Json.error.message ?? $Call.Raw)"
    Write-Step "$Label tools/call ListTenants" $Ok "HTTP $($Call.Status) $($Text.Substring(0, [Math]::Min(300, $Text.Length)))"
}

function Invoke-Flow([ValidateSet('Public', 'Confidential')][string]$Flow) {
    Write-Host "`n=== $Flow flow against $McpUrl ===" -ForegroundColor Cyan

    $Probe = Invoke-WebRequest -Uri $McpUrl -Method Post -ContentType 'application/json' -Body '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{}}' -SkipHttpErrorCheck -MaximumRedirection 0 -ErrorAction SilentlyContinue
    $Challenge = "$($Probe.Headers['WWW-Authenticate'])"
    Write-Step 'Unauthenticated request is challenged' ($Probe.StatusCode -eq 401 -and $Challenge) "HTTP $($Probe.StatusCode) WWW-Authenticate: $Challenge$(if ($Probe.Headers['Location']) { "`nLocation: $($Probe.Headers['Location'])" })"
    $ChallengeScope = [regex]::Match($Challenge, 'scope="([^"]*)"').Groups[1].Value
    $MetadataUrl = [regex]::Match($Challenge, 'resource_metadata="([^"]*)"').Groups[1].Value

    $Prm = Invoke-RestMethod -Uri ($MetadataUrl ? $MetadataUrl : "$BaseUrl/.well-known/oauth-protected-resource/api/ExecMcp")
    Write-Step 'Protected resource metadata' ([bool]$Prm.resource) "resource=$($Prm.resource) scopes=$($Prm.scopes_supported -join ' ')"
    $As = Invoke-RestMethod -Uri "$($Prm.authorization_servers[0].TrimEnd('/'))/.well-known/oauth-authorization-server"
    Write-Step 'Authorization server metadata' ([bool]$As.token_endpoint) "authorize=$($As.authorization_endpoint)`ntoken=$($As.token_endpoint)`nregistration=$($As.registration_endpoint)"

    $Scope = $ChallengeScope ? $ChallengeScope : ($Prm.scopes_supported -join ' ')
    $FlowClientId = $ClientId
    if ($Flow -eq 'Public') {
        $Port = Get-Random -Minimum 49152 -Maximum 65000
        $RedirectUri = "http://127.0.0.1:$Port"
        if (-not $FlowClientId) {
            $Registration = Invoke-WebRequest -Uri $As.registration_endpoint -Method Post -ContentType 'application/json' -SkipHttpErrorCheck -Body (@{
                    client_name                = 'Test-CippMcpAuth'
                    redirect_uris              = @($RedirectUri)
                    grant_types                = @('authorization_code', 'refresh_token')
                    response_types             = @('code')
                    token_endpoint_auth_method = 'none'
                } | ConvertTo-Json -Compress)
            $FlowClientId = ($Registration.Content | ConvertFrom-Json).client_id
            Write-Step 'Dynamic client registration' ([bool]$FlowClientId) "HTTP $($Registration.StatusCode) $($Registration.Content)"
        }
    } else {
        if (-not $FlowClientId -or -not $ClientSecret) { throw 'Confidential mode needs -ClientId and -ClientSecret (or $env:CIPP_MCP_CLIENT_SECRET).' }
        $RedirectUri = $ConfidentialRedirectUri
    }

    $Verifier = ConvertTo-Base64Url ([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
    $UsePkce = $Flow -eq 'Public' -or -not $NoPkce
    $State = [guid]::NewGuid().ToString('N')
    $AuthorizeQuery = [ordered]@{
        client_id     = $FlowClientId
        response_type = 'code'
        redirect_uri  = $RedirectUri
        scope         = $Scope
        state         = $State
        prompt        = 'select_account'
    }
    if ($UsePkce) {
        $AuthorizeQuery.code_challenge = ConvertTo-Base64Url ([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::ASCII.GetBytes($Verifier)))
        $AuthorizeQuery.code_challenge_method = 'S256'
    }
    if ($UseResourceIndicator) { $AuthorizeQuery.resource = $Prm.resource }
    $AuthorizeUrl = $As.authorization_endpoint + '?' + (($AuthorizeQuery.GetEnumerator() | ForEach-Object { "$($_.Key)=$([uri]::EscapeDataString($_.Value))" }) -join '&')
    Write-Host "       client_id=$FlowClientId redirect_uri=$RedirectUri pkce=$UsePkce scope=$Scope"

    $Callback = Wait-OAuthCallback $RedirectUri $AuthorizeUrl
    Write-Step 'Authorize redirect' ($Callback.code -and $Callback.state -eq $State) ($Callback.code ? 'code received' : "$($Callback.error): $($Callback.error_description)")

    $TokenBody = @{ grant_type = 'authorization_code'; client_id = $FlowClientId; code = $Callback.code; redirect_uri = $RedirectUri; scope = $Scope }
    if ($UsePkce) { $TokenBody.code_verifier = $Verifier }
    if ($Flow -eq 'Confidential') { $TokenBody.client_secret = $ClientSecret }
    $Token = Invoke-TokenRequest $As.token_endpoint $TokenBody
    Write-Step 'Code exchange' ($Token.Status -eq 200) ($Token.Status -eq 200 ? "refresh_token issued: $([bool]$Token.Json.refresh_token)" : "$($Token.Json.error): $($Token.Json.error_description)")
    Write-Step 'Access token claims' $true (Get-TokenSummary $Token.Json.access_token)

    Test-McpSession $Token.Json.access_token 'MCP'

    if (-not $Token.Json.refresh_token) {
        Write-Step 'Refresh token' $false 'No refresh_token was issued (offline_access missing from scope or not consented).'
    }
    $RefreshBody = @{ grant_type = 'refresh_token'; client_id = $FlowClientId; refresh_token = $Token.Json.refresh_token }
    if ($UseResourceIndicator) { $RefreshBody.resource = $Prm.resource } else { $RefreshBody.scope = $Scope }
    if ($Flow -eq 'Confidential') { $RefreshBody.client_secret = $ClientSecret }
    $Refreshed = Invoke-TokenRequest $As.token_endpoint $RefreshBody
    Write-Step 'Refresh token grant' ($Refreshed.Status -eq 200) ($Refreshed.Status -eq 200 ? (Get-TokenSummary $Refreshed.Json.access_token) : "$($Refreshed.Json.error): $($Refreshed.Json.error_description)")

    Test-McpSession $Refreshed.Json.access_token 'MCP (refreshed token)'
}

$Flows = $Mode -eq 'Both' ? @('Public', 'Confidential') : @($Mode)
$Results = foreach ($Flow in $Flows) {
    try {
        Invoke-Flow $Flow
        [PSCustomObject]@{ Flow = $Flow; Result = 'PASS'; Detail = '' }
    } catch {
        [PSCustomObject]@{ Flow = $Flow; Result = 'FAIL'; Detail = $_.Exception.Message }
    }
}
Write-Host ''
$Results | Format-Table -AutoSize

function Invoke-CIPPCloudBackupAzureBlobRequest {
    <#
    .SYNOPSIS
        Sends a Blob service request to an Azure Blob cloud backup destination and returns @{ StatusCode; Headers; Body }.
    .DESCRIPTION
        Throws ItemNotFoundException when the container is missing and a provider error for any other failure,
        unless the status code is listed in -AllowStatus.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [ValidateSet('GET', 'HEAD', 'PUT', 'DELETE')]
        [string]$Method = 'GET',

        [string]$Key,

        [System.Collections.IDictionary]$Query,

        [byte[]]$Body,

        [string]$ContentType,

        [hashtable]$Headers,

        [int[]]$AllowStatus
    )

    $Account = [string]$Destination.StorageAccount
    $Container = [string]$Destination.Container
    if ($Account -notmatch '^[a-z0-9]{3,24}$') {
        throw [System.ArgumentException]::new("'$Account' is not a valid storage account name.")
    }
    if ($Container -notmatch '^(?!.*--)[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$') {
        throw [System.ArgumentException]::new("'$Container' is not a valid container name.")
    }
    if ($Destination.AuthMode -eq 'CippApp') {
        $Authorization = (Get-GraphToken -tenantid $env:TenantID -scope 'https://storage.azure.com/.default' -AsApp $true).Authorization
    } else {
        if (-not $Destination.AzureTenantId -or -not $Destination.ClientId -or -not $Destination.Secret) {
            throw [System.ArgumentException]::new('The destination needs a tenant id, client id and client secret.')
        }
        $Token = Get-CIPPClientCredentialToken -TenantId $Destination.AzureTenantId -ClientId $Destination.ClientId -ClientSecret $Destination.Secret -Scope 'https://storage.azure.com/.default'
        $Authorization = "Bearer $Token"
    }

    $Uri = "https://$Account.blob.core.windows.net/$Container"
    if ($Key) {
        $Uri = $Uri + '/' + (@(foreach ($Segment in $Key.Split('/')) { [uri]::EscapeDataString($Segment) }) -join '/')
    }
    if ($Query -and $Query.Count -gt 0) {
        $Uri = $Uri + '?' + (@(foreach ($Name in $Query.Keys) { '{0}={1}' -f $Name, [uri]::EscapeDataString([string]$Query[$Name]) }) -join '&')
    }

    $RequestHeaders = @{
        Authorization  = $Authorization
        'x-ms-version' = '2023-11-03'
        'x-ms-date'    = [datetime]::UtcNow.ToString('R')
    }
    if ($Headers) {
        foreach ($Name in $Headers.Keys) { $RequestHeaders[$Name] = $Headers[$Name] }
    }

    $RequestParams = @{
        Uri                = $Uri
        Method             = $Method
        Headers            = $RequestHeaders
        SkipHttpErrorCheck = $true
        ErrorAction        = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $RequestParams.Body = $Body
        $RequestParams.ContentType = if ($ContentType) { $ContentType } else { 'application/octet-stream' }
    }

    # Invoke-WebRequest because blob bodies are binary; Invoke-CIPPRestMethod returns responses as text.
    $Attempt = 0
    do {
        $Attempt++
        try {
            $Response = Invoke-WebRequest @RequestParams
        } catch {
            throw "Could not reach storage account '$Account': $($_.Exception.Message)"
        }
        $StatusCode = [int]$Response.StatusCode
        $Retry = ($StatusCode -eq 429 -or $StatusCode -ge 500) -and $Attempt -lt 4
        if ($Retry) { Start-Sleep -Seconds ([Math]::Pow(2, $Attempt)) }
    } while ($Retry)

    $ResponseBody = [byte[]]::new(0)
    if ($Response.RawContentStream) { $ResponseBody = $Response.RawContentStream.ToArray() }
    $Result = @{ StatusCode = $StatusCode; Headers = $Response.Headers; Body = $ResponseBody }
    if ($StatusCode -lt 400) { return $Result }

    $ErrorCode = $null
    $ErrorMessage = $null
    if ($ResponseBody.Length -gt 0) {
        try {
            $ErrorXml = [xml]([System.Text.Encoding]::UTF8.GetString($ResponseBody).TrimStart([char]0xFEFF))
            $ErrorCode = $ErrorXml.Error.Code
            $ErrorMessage = ([string]$ErrorXml.Error.Message).Split("`n")[0].Trim()
        } catch {
            $ErrorMessage = $null
        }
    }
    if (-not $ErrorCode -and $Response.Headers) {
        $ErrorCode = @($Response.Headers['x-ms-error-code'])[0]
    }

    if ($ErrorCode -eq 'ContainerNotFound') {
        throw [System.Management.Automation.ItemNotFoundException]::new("Container '$Container' was not found in storage account '$Account'.")
    }
    if ($AllowStatus -contains $StatusCode) {
        $Result.ErrorCode = $ErrorCode
        return $Result
    }
    if (-not $ErrorMessage) { $ErrorMessage = 'no error details were returned' }
    $Exception = [System.Management.Automation.RuntimeException]::new("Azure Storage returned $StatusCode ($ErrorCode): $ErrorMessage")
    $Exception.Data['StatusCode'] = $StatusCode
    $Exception.Data['ErrorCode'] = $ErrorCode
    throw $Exception
}

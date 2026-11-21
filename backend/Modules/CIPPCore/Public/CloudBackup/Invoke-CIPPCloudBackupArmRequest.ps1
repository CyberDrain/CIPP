function Invoke-CIPPCloudBackupArmRequest {
    <#
    .SYNOPSIS
        Sends an Azure Resource Manager request as CIPP's managed identity and returns { StatusCode; Body }.
    .DESCRIPTION
        -Path is relative to https://management.azure.com. Throttling and server errors are retried. A status of 400 or
        more throws, with StatusCode and ErrorCode in the exception's Data, unless it is listed in -AllowStatus. With
        -Wait an accepted long-running operation is polled until it finishes and the resource is read again.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('GET', 'PUT', 'POST', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^/subscriptions(/|\?|$)')]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ApiVersion,

        $Body,

        [int[]]$AllowStatus,

        [switch]$Wait,

        [ValidateRange(1, 1000)]
        [int]$MaxPolls = 90
    )

    $Uri = 'https://management.azure.com{0}{1}api-version={2}' -f $Path, $(if ($Path.Contains('?')) { '&' } else { '?' }), $ApiVersion
    $RequestParams = @{
        Uri                = $Uri
        Method             = $Method
        Headers            = @{ Authorization = "Bearer $(Get-CIPPAzIdentityToken -ResourceUrl 'https://management.azure.com/')" }
        SkipHttpErrorCheck = $true
        ErrorAction        = 'Stop'
    }
    if ($null -ne $Body) {
        $RequestParams.Body = [CIPP.CippJson]::ToJson($Body, 20) ?? (ConvertTo-Json -InputObject $Body -Depth 20 -Compress)
        $RequestParams.ContentType = 'application/json'
    }

    $Attempt = 0
    do {
        $Attempt++
        $Raw = Invoke-WebRequest @RequestParams
        $StatusCode = [int]$Raw.StatusCode
        $Retry = ($StatusCode -eq 429 -or $StatusCode -ge 500) -and $Attempt -lt 4
        if ($Retry) {
            $Seconds = [int]"$(@($Raw.Headers['Retry-After'])[0])"
            if ($Seconds -le 0) { $Seconds = [int][Math]::Pow(2, $Attempt) }
            Start-Sleep -Seconds ([Math]::Min([Math]::Max($Seconds, 1), 60))
        }
    } while ($Retry)
    $Response = if ($Raw.Content) { try { [CIPP.CippJson]::ConvertFromJson([string]$Raw.Content) } catch { $null } }

    if ($StatusCode -ge 400) {
        if ($AllowStatus -contains $StatusCode) { return [pscustomobject]@{ StatusCode = $StatusCode; Body = $Response } }
        $ErrorCode = "$($Response.error.code)"
        $ErrorText = if ($Response.error.message) { "$($Response.error.message)" } else { 'no error details were returned' }
        $Exception = [System.Management.Automation.RuntimeException]::new("Azure Resource Manager returned $StatusCode ($ErrorCode): $ErrorText")
        $Exception.Data['StatusCode'] = $StatusCode
        $Exception.Data['ErrorCode'] = $ErrorCode
        throw $Exception
    }

    if (-not $Wait -or $StatusCode -notin @(201, 202)) {
        return [pscustomobject]@{ StatusCode = $StatusCode; Body = $Response }
    }

    # https://learn.microsoft.com/azure/azure-resource-manager/management/async-operations
    $UsesAsyncOperation = [bool]"$(@($Raw.Headers['Azure-AsyncOperation'])[0])"
    $PollUri = if ($UsesAsyncOperation) { "$(@($Raw.Headers['Azure-AsyncOperation'])[0])" } else { "$(@($Raw.Headers['Location'])[0])" }
    if (-not $PollUri) { return [pscustomobject]@{ StatusCode = $StatusCode; Body = $Response } }
    $ParsedPollUri = $null
    if (-not [uri]::TryCreate($PollUri, [System.UriKind]::Absolute, [ref]$ParsedPollUri) -or $ParsedPollUri.Scheme -ne 'https' -or $ParsedPollUri.Host -ne 'management.azure.com') {
        throw "Azure Resource Manager returned an unexpected operation URL: $PollUri"
    }

    $Seconds = [int]"$(@($Raw.Headers['Retry-After'])[0])"
    for ($Poll = 1; $Poll -le $MaxPolls; $Poll++) {
        Start-Sleep -Seconds ([Math]::Min([Math]::Max($(if ($Seconds -gt 0) { $Seconds } else { 10 }), 1), 60))
        $PollRaw = Invoke-WebRequest -Uri $ParsedPollUri -Method 'GET' -Headers @{ Authorization = "Bearer $(Get-CIPPAzIdentityToken -ResourceUrl 'https://management.azure.com/')" } -SkipHttpErrorCheck -ErrorAction 'Stop'
        $PollStatus = [int]$PollRaw.StatusCode
        $Seconds = [int]"$(@($PollRaw.Headers['Retry-After'])[0])"
        if ($PollStatus -eq 429 -or $PollStatus -ge 500) { continue }
        $Operation = if ($PollRaw.Content) { try { [CIPP.CippJson]::ConvertFromJson([string]$PollRaw.Content) } catch { $null } }

        $OperationError = $null
        if ($PollStatus -ge 400) {
            $OperationError = $Operation.error ?? [pscustomobject]@{ code = "$PollStatus"; message = $null }
        } elseif ($UsesAsyncOperation -and $Operation.status -in @('Failed', 'Canceled')) {
            $OperationError = $Operation.error ?? $Operation.properties.error ?? [pscustomobject]@{ code = "$($Operation.status)"; message = $null }
        }
        if ($OperationError) {
            $Exception = [System.Management.Automation.RuntimeException]::new("Azure Resource Manager could not finish the operation on $Path ($($OperationError.code)): $($OperationError.message ?? 'no error details were returned')")
            $Exception.Data['StatusCode'] = $PollStatus
            $Exception.Data['ErrorCode'] = "$($OperationError.code)"
            throw $Exception
        }

        $Finished = if ($UsesAsyncOperation) { $Operation.status -eq 'Succeeded' } else { $PollStatus -ne 202 }
        if ($Finished) {
            return Invoke-CIPPCloudBackupArmRequest -Method 'GET' -Path $Path -ApiVersion $ApiVersion
        }
    }
    throw "Azure Resource Manager did not finish the operation on $Path after $MaxPolls checks."
}

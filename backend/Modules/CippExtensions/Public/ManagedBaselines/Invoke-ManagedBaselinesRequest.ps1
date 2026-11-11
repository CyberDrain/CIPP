function Invoke-ManagedBaselinesRequest {
    <#
    .SYNOPSIS
        Calls the CyberDrain Managed Baselines service.
    .DESCRIPTION
        The only function that talks to the service, so an instance that has not enabled the
        integration never calls it. Sends the extension's API key as x-api-key and turns a
        refusal into a message an operator can act on.
        With CIPP_MANAGED_BASELINES_MOCK set to 'true' nothing leaves the instance: answers come
        from Config/ManagedBaselineSamples, and a request reports ready two minutes after its
        snapshot was sent.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('GET', 'POST', 'DELETE')][string]$Method = 'GET',
        $Body
    )

    $Path = $Path.Trim('/')
    if ($Path -notmatch '^[\w/-]+$') {
        throw [System.ArgumentException]::new("'$Path' is not a valid Managed Baselines address.")
    }

    $ConfigTable = Get-CippTable -tablename 'Extensionsconfig'
    $Config = $(try { (Get-CIPPAzDataTableEntity @ConfigTable).config | ConvertFrom-Json -ErrorAction Stop } catch { $null })
    if ($Config.CyberDrainManagedBaselines.Enabled -ne $true) {
        throw [System.ArgumentException]::new('The CyberDrain Managed Baselines integration is not enabled. Enable it under Integrations.')
    }

    if ($env:CIPP_MANAGED_BASELINES_MOCK -eq 'true') {
        $Samples = Join-Path $env:CIPPRootPath 'Config/ManagedBaselineSamples'
        switch -Regex ("$Method $Path") {
            '^GET account$' {
                return [PSCustomObject]@{ partnerName = 'Sample Partner'; plan = 'Sample'; mock = $true }
            }
            '^GET templates$' {
                return [System.IO.File]::ReadAllText((Join-Path $Samples 'catalog.json')) | ConvertFrom-Json -Depth 100
            }
            '^GET templates/([\w-]+)$' {
                $File = Join-Path $Samples "template-$($Matches[1]).json"
                if (-not (Test-Path -LiteralPath $File)) {
                    throw [System.Management.Automation.ItemNotFoundException]::new("CyberDrain has no published baseline with the id '$($Matches[1])'.")
                }
                return [System.IO.File]::ReadAllText($File) | ConvertFrom-Json -Depth 100
            }
            '^POST requests$' {
                return [PSCustomObject]@{ requestId = "$($Body.requestId)"; status = 'submitted'; mock = $true }
            }
            '^GET requests/([\w-]+)$' {
                $RequestId = $Matches[1]
                $Table = Get-CippTable -tablename 'ManagedBaselineRequests'
                $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'request' and RowKey eq '$RequestId'" | Select-Object -First 1
                $SubmittedAt = [int64]($Row.SubmittedAt ?? 0)
                $Status = 'submitted'
                if ("$($Row.Status)" -eq 'Implemented') {
                    $Status = 'implemented'
                } elseif ($SubmittedAt -gt 0 -and ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $SubmittedAt) -ge 120) {
                    $Status = 'ready'
                }
                $Answer = [PSCustomObject]@{ requestId = $RequestId; status = $Status; engineerNotes = ''; version = $null; package = $null; mock = $true }
                if ($Status -ne 'submitted') {
                    $Answer.package = [System.IO.File]::ReadAllText((Join-Path $Samples 'custom-package.json')) | ConvertFrom-Json -Depth 100
                    $Answer.version = $Answer.package.version
                    $Answer.engineerNotes = 'Sample delivery from mock mode.'
                }
                return $Answer
            }
            '^POST requests/[\w-]+/confirm$' {
                return [PSCustomObject]@{ status = 'implemented'; mock = $true }
            }
            '^DELETE requests/[\w-]+$' {
                return
            }
            default {
                throw [System.ArgumentException]::new("The sample service has no answer for $Method $Path.")
            }
        }
    }

    $APIKey = Get-ExtensionAPIKey -Extension 'CyberDrainManagedBaselines'
    if ([string]::IsNullOrWhiteSpace($APIKey)) {
        throw [System.ArgumentException]::new('No API key is saved for CyberDrain Managed Baselines. Add it under Integrations.')
    }

    $BaseUrl = 'https://managedbaselines.cipp.app'
    if ($env:CIPP_MANAGED_BASELINES_URL) { $BaseUrl = $env:CIPP_MANAGED_BASELINES_URL.TrimEnd('/') }
    $RestMethod = @{
        Uri     = '{0}/api/{1}' -f $BaseUrl, $Path
        Method  = $Method
        Headers = @{ 'x-api-key' = $APIKey; 'User-Agent' = 'CIPP' }
    }
    if ($null -ne $Body) {
        $RestMethod.Body = ConvertTo-Json -InputObject $Body -Depth 100 -Compress
        $RestMethod.ContentType = 'application/json'
    }

    try {
        Invoke-RestMethod @RestMethod
    } catch {
        switch ([int]$_.Exception.Response.StatusCode.value__) {
            401 { throw [System.UnauthorizedAccessException]::new('CyberDrain rejected the API key. Check the key under Integrations.') }
            402 { throw [System.UnauthorizedAccessException]::new('The Managed Baselines subscription for this API key is not active.') }
            403 { throw [System.UnauthorizedAccessException]::new('CyberDrain rejected the API key. Check the key under Integrations.') }
            404 { throw [System.Management.Automation.ItemNotFoundException]::new('CyberDrain could not find that baseline or request.') }
            429 { throw 'CyberDrain is rate limiting this instance. Try again in a few minutes.' }
            default { throw "The Managed Baselines service could not be reached: $($_.Exception.Message)" }
        }
    }
}

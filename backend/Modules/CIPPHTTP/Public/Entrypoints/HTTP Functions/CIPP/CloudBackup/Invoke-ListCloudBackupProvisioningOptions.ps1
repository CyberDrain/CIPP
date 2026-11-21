function Invoke-ListCloudBackupProvisioningOptions {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.Read
    .SYNOPSIS
        List the Azure subscriptions and regions CIPP can create cloud backup storage in
    .DESCRIPTION
        Reports whether CIPP can create an Azure storage account for cloud backups with its managed identity, which needs Contributor and User Access Administrator on a subscription. Lists the subscriptions the managed identity can see and, with SubscriptionId, that subscription's regions. When Available is false, Reason says why and destinations are set up manually.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Optional subscription id to also list its regions
    $SubscriptionId = "$($Request.Query.SubscriptionId)".Trim()
    if ($SubscriptionId -and -not ($SubscriptionId -as [guid])) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'SubscriptionId must be a subscription id (GUID)' }
            })
    }

    if (-not [System.Environment]::GetEnvironmentVariable('IDENTITY_ENDPOINT') -or -not [System.Environment]::GetEnvironmentVariable('IDENTITY_HEADER')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = [pscustomobject]@{
                    Available       = $false
                    Reason          = 'this CIPP install has no managed identity.'
                    ManagedIdentity = $null
                    Subscriptions   = @()
                    Regions         = @()
                }
            })
    }

    try {
        $Token = Get-CIPPAzIdentityToken -ResourceUrl 'https://management.azure.com/'
        $Claims = $null
        $Parts = "$Token".Split('.')
        if ($Parts.Count -ge 2) {
            $Payload = $Parts[1].Replace('-', '+').Replace('_', '/')
            $Payload = $Payload.PadRight($Payload.Length + (4 - $Payload.Length % 4) % 4, '=')
            $Claims = try { [CIPP.CippJson]::ConvertFromJson([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Payload))) } catch { $null }
        }
        $ManagedIdentity = [pscustomobject]@{
            PrincipalId = if ($Claims.oid) { "$($Claims.oid)" } else { $null }
            ResourceId  = if ($Claims.xms_mirid) { "$($Claims.xms_mirid)" } else { $null }
        }

        $Listed = Invoke-CIPPCloudBackupArmRequest -Path '/subscriptions' -ApiVersion '2022-12-01'
        $Subscriptions = @(foreach ($Subscription in @($Listed.Body.value)) {
                if ($Subscription.state -ne 'Enabled') { continue }
                [pscustomobject]@{ id = "$($Subscription.subscriptionId)"; name = "$($Subscription.displayName)" }
            })

        $Regions = @()
        if ($SubscriptionId) {
            if (-not $Subscriptions.Where({ $_.id -eq $SubscriptionId }, 'First')) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body       = @{ Results = "CIPP's managed identity cannot see subscription $SubscriptionId" }
                    })
            }
            $Locations = Invoke-CIPPCloudBackupArmRequest -Path "/subscriptions/$SubscriptionId/locations" -ApiVersion '2022-12-01'
            $Regions = @(foreach ($Location in @($Locations.Body.value)) {
                    if ($Location.metadata.regionType -and $Location.metadata.regionType -ne 'Physical') { continue }
                    [pscustomobject]@{ name = "$($Location.name)"; displayName = "$($Location.displayName)" }
                })
        }

        $Body = [pscustomobject]@{
            Available       = $Subscriptions.Count -gt 0
            Reason          = if ($Subscriptions.Count -eq 0) { "CIPP's managed identity has no access to any subscription yet." } else { $null }
            ManagedIdentity = $ManagedIdentity
            Subscriptions   = $Subscriptions
            Regions         = $Regions
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Could not read the Azure subscriptions of CIPP's managed identity: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message $Message -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = @{ Results = $Message }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

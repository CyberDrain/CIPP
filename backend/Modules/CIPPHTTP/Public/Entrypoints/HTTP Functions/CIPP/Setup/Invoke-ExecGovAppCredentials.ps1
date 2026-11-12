function Invoke-ExecGovAppCredentials {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    .SYNOPSIS
        Status and configuration of the Azure Government app registration used for direct GCC High and DoD tenants.
    .DESCRIPTION
        Actions: Status (default) reports what is configured without returning any secret; Save stores the application id and, when given, a new client secret; GenerateCertificate creates a certificate for the app, stores its private key next to the SAM certificate and returns only the public certificate to upload to the app registration.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Action = $Request.Body.Action ?? $Request.Query.Action ?? 'Status'

    $Origin = if ($Request.Headers.'x-ms-original-url') {
        ($Request.Headers.'x-ms-original-url' -split '/api/')[0]
    } else {
        $Request.Headers.origin ?? $Request.Headers.referer?.TrimEnd('/')
    }

    # The Azure Government app signs in to every government direct tenant, and only an unrestricted
    # caller can add those tenants (ExecAddTenant): replacing its credentials needs the same scope.
    if ($Action -in @('Save', 'GenerateCertificate')) {
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants') {
            return [HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body       = @{ Results = 'Changing the Azure Government app credentials requires unrestricted tenant access.' }
            }
        }
    }

    try {
        switch ($Action) {
            'Status' {
                $Credential = Get-CIPPGovAppCredential -Force
                $Certificate = @{ configured = $false }
                if ($Credential.HasCertificate) {
                    try {
                        $Cert = Get-CIPPSAMCertificate -Name 'GovSAMCertificate' -SkipCache -ErrorAction Stop
                        $Certificate = @{
                            configured        = $true
                            thumbprint        = $Cert.Thumbprint
                            notAfter          = $Cert.NotAfter
                            # Public part only (DER, base64) - what the app registration needs.
                            publicCertificate = [Convert]::ToBase64String($Cert.Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
                        }
                    } catch {
                        $Certificate = @{ configured = $true; error = 'The stored certificate could not be read.' }
                    }
                }
                $Endpoint = Get-CIPPCloudEndpoint -CloudEnvironment 'USGovHigh'
                # Which credential the gov app signs in with - the same rule as Get-CIPPCloudTokenRoute:
                # the certificate when the instance uses certificate authentication or no secret is
                # stored, the secret otherwise. The feature flag is what $env:CertificateAuthMode mirrors.
                $CertificateAuthMode = try {
                    (Get-CIPPFeatureFlag -Id 'CertificateAuthentication').Enabled -eq $true
                } catch {
                    [bool]$env:CertificateAuthMode
                }
                $CredentialInUse = if ($CertificateAuthMode -or -not $Credential.HasSecret) { 'certificate' } else { 'secret' }
                $Results = @{
                    configured          = [bool]$Credential.Configured
                    applicationId       = $Credential.ApplicationId
                    hasSecret           = [bool]$Credential.HasSecret
                    certificateAuthMode = [bool]$CertificateAuthMode
                    credentialInUse     = $CredentialInUse
                    certificate         = $Certificate
                    authority     = "$($Endpoint.Authority)/organizations"
                    redirectUri   = if ($Origin) { "$Origin/authredirect" } else { $null }
                }
                $Body = @{ Results = $Results }
                $StatusCode = [HttpStatusCode]::OK
            }
            'Save' {
                $ApplicationId = [string]($Request.Body.applicationId.value ?? $Request.Body.applicationId)
                $ApplicationSecret = [string]$Request.Body.applicationSecret
                if ($ApplicationId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\z') {
                    $StatusCode = [HttpStatusCode]::BadRequest
                    $Body = @{ Results = 'A valid application (client) id is required.' }
                    break
                }
                $Params = @{ ApplicationId = $ApplicationId }
                if (-not [string]::IsNullOrWhiteSpace($ApplicationSecret)) { $Params.ApplicationSecret = $ApplicationSecret }
                Set-CIPPGovAppCredential @Params
                $What = if ($Params.ApplicationSecret) { 'application id and client secret' } else { 'application id' }
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Updated the Azure Government app registration's $What (application id $ApplicationId)." -Sev 'Alert'
                $Body = @{ Results = @{ message = "Saved the Azure Government app $What."; severity = 'success' } }
                $StatusCode = [HttpStatusCode]::OK
            }
            'GenerateCertificate' {
                $InstanceName = if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') { [System.Environment]::MachineName } else { $env:WEBSITE_SITE_NAME }
                $New = New-CIPPSAMCertificate -SubjectName "CN=CIPP-SAM-Gov-$InstanceName"
                $null = Set-CIPPSAMCertificate -PfxBase64 $New.PfxBase64 -Name 'GovSAMCertificate'
                $Stored = Get-CIPPSAMCertificate -Name 'GovSAMCertificate' -SkipCache -ErrorAction Stop
                Remove-Item -Path env:CIPPGovAppLoaded -ErrorAction SilentlyContinue
                $null = Set-CIPPCredentialVersion
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Generated a new Azure Government app certificate (thumbprint $($Stored.Thumbprint)). Upload it to the app registration in Azure Government." -Sev 'Alert'
                $Body = @{
                    Results = @{
                        message           = "Generated a certificate (thumbprint $($Stored.Thumbprint)). Upload it to the Azure Government app registration under Certificates & secrets."
                        severity          = 'success'
                        thumbprint        = $Stored.Thumbprint
                        notAfter          = $Stored.NotAfter
                        publicCertificate = [Convert]::ToBase64String($Stored.Certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
                    }
                }
                $StatusCode = [HttpStatusCode]::OK
            }
            default {
                $StatusCode = [HttpStatusCode]::BadRequest
                $Body = @{ Results = "Unknown action. Use 'Status', 'Save' or 'GenerateCertificate'." }
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Azure Government app credential request ($Action) failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ Results = "Failed: $($ErrorMessage.NormalizedError)" }
    }

    return [HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $Body
    }
}

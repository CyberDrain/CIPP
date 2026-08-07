function Invoke-AddIntuneTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Endpoint.MEM.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $GUID = (New-Guid).GUID
    try {
        if ($Request.Body.RawJSON) {
            if (!$Request.Body.displayName) { throw 'You must enter a displayName' }

            # Nothing has been stored yet, so refusing costs the caller nothing and keeps a template
            # that cannot deploy out of the list entirely.
            $Validation = Test-CIPPIntuneTemplate -RawJSON $Request.Body.RawJSON -TemplateType $Request.Body.TemplateType -DisplayName $Request.Body.displayName
            if (-not $Validation.IsValid) {
                throw "The template was not saved because it would not deploy: $($Validation.Errors -join ' ')"
            }

            $reusableTemplateRefs = @()
            $object = [PSCustomObject]@{
                Displayname      = $Request.Body.displayName
                Description      = $Request.Body.description
                RAWJson          = $Request.Body.RawJSON
                Type             = $Request.Body.TemplateType
                GUID             = $GUID
                ReusableSettings = $reusableTemplateRefs
            } | ConvertTo-Json
            $Table = Get-CippTable -tablename 'templates'
            $Table.Force = $true
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON                  = "$object"
                ReusableSettingsCount = $reusableTemplateRefs.Count
                RowKey                = "$GUID"
                PartitionKey          = 'IntuneTemplate'
                GUID                  = "$GUID"
            }
            Write-LogMessage -headers $Headers -API $APIName -message "Created intune policy template named $($Request.Body.displayName) with GUID $GUID" -Sev 'Debug'

            $Result = 'Successfully added template'
            $StatusCode = [HttpStatusCode]::OK
        } else {
            $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
            $URLName = $Request.Body.URLName ?? $Request.Query.URLName
            $ID = $Request.Body.ID ?? $Request.Query.ID
            $ODataType = $Request.Body.ODataType ?? $Request.Query.ODataType
            $Template = New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName $URLName -ID $ID -ODataType $ODataType

            $reusableResult = Get-CIPPReusableSettingsFromPolicy -PolicyJson $Template.TemplateJson -Tenant $TenantFilter -Headers $Headers -APIName $APIName
            $reusableTemplateRefs = $reusableResult.ReusableSettings
            # Intune templates store payload in RAWJson; only the content is rewritten to use reusable template GUID placeholders.
            $templateJson = if ($reusableResult.RawJSON) { $reusableResult.RawJSON } else { $Template.TemplateJson }

            # A capture reads a policy Intune is already running, so this should always pass. When it
            # does not, the capture dropped something the policy needs and storing it would produce a
            # template that silently fails to deploy later.
            $Validation = Test-CIPPIntuneTemplate -RawJSON $templateJson -TemplateType $Template.Type -DisplayName $Template.DisplayName
            if (-not $Validation.IsValid) {
                throw "The captured policy did not produce a deployable template: $($Validation.Errors -join ' ')"
            }

            $object = [PSCustomObject]@{
                Displayname      = $Template.DisplayName
                Description      = $Template.Description
                RAWJson          = $templateJson
                Type             = $Template.Type
                GUID             = $GUID
                ReusableSettings = $reusableTemplateRefs
            } | ConvertTo-Json -Compress
            $Table = Get-CippTable -tablename 'templates'
            $Table.Force = $true
            Add-CIPPAzDataTableEntity @Table -Entity @{
                JSON         = "$object"
                RowKey       = "$GUID"
                PartitionKey = 'IntuneTemplate'
            }
            Write-LogMessage -headers $Headers -API $APIName -message "Created intune policy template $($Request.Body.displayName) with GUID $GUID using an original policy from a tenant" -Sev 'Debug'

            $Result = 'Successfully added template'
            $StatusCode = [HttpStatusCode]::OK
        }
    } catch {
        $StatusCode = [HttpStatusCode]::InternalServerError
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Intune Template Deployment failed: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
    }


    # The GUID rides along so the caller can go straight to the template it just made. Creating one
    # from scratch stores a name and a set of settings but no values yet, so the next thing anyone
    # does is open it - and without this there is nothing to open it by.
    $Body = @{ 'Results' = $Result }
    if ($StatusCode -eq [HttpStatusCode]::OK) { $Body.GUID = $GUID }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

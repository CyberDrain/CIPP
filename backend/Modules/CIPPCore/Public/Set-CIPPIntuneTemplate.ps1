function Set-CIPPIntuneTemplate {
    <#
    .SYNOPSIS
        Stores an Intune policy template.

    .PARAMETER PayloadChanged
        Set when the caller is writing a new policy payload rather than only changing the name,
        description or package. It decides whether validation refuses the write.

        A template that is already broken - most often one imported before its type could be
        determined - must stay editable, because refusing to save a rename would leave the owner
        unable to touch it at all without fixing something this screen cannot fix. So a pre-existing
        problem is logged and the write goes ahead. A problem in a payload the caller is submitting
        now is refused: that is someone replacing a working template with one that cannot deploy,
        which is exactly what there is to prevent.
    #>
    param (
        [Parameter(Mandatory = $true)]
        $RawJSON,
        $GUID,
        $DisplayName,
        $Description,
        $templateType,
        $Package,
        $Headers,
        [switch]$PayloadChanged
    )
    $APIName = 'Set-CIPPIntuneTemplate'
    if (!$DisplayName) { throw 'You must enter a displayname' }

    $Validation = Test-CIPPIntuneTemplate -RawJSON $RawJSON -TemplateType $templateType -DisplayName $DisplayName
    if (-not $Validation.IsValid) {
        $Reason = $Validation.Errors -join ' '
        if ($PayloadChanged) {
            throw "The template was not saved because it would not deploy: $Reason"
        }
        Write-LogMessage -Headers $Headers -API $APIName -message "Saved template '$DisplayName' ($GUID) despite existing problems, because this edit did not change the policy: $Reason" -Sev 'Warning'
    }
    foreach ($Warning in $Validation.Warnings) {
        Write-LogMessage -Headers $Headers -API $APIName -message "Template '$DisplayName' ($GUID): $Warning" -Sev 'Warning'
    }

    $object = [PSCustomObject]@{
        Displayname = $DisplayName
        Description = $Description
        RAWJson     = $RawJSON
        Type        = $templateType
        GUID        = $GUID
    } | ConvertTo-Json -Depth 10 -Compress
    $Table = Get-CippTable -tablename 'templates'
    $Table.Force = $true
    Add-CIPPAzDataTableEntity @Table -Entity @{
        JSON         = "$object"
        RowKey       = "$GUID"
        GUID         = "$GUID"
        Package      = "$Package"
        PartitionKey = 'IntuneTemplate'
    }
    Write-LogMessage -Headers $Headers -API $APIName -message "Created intune policy template named $DisplayName with GUID $GUID" -Sev 'Debug'

    return 'Successfully added template'
}

function New-CIPPCACoverageReason {
    param (
        [string]$Type,
        [string]$Id,
        [string]$Token,
        [string]$Label,
        [bool]$Transitive = $false,
        [string]$ViaGroupId,
        [string]$ViaGroupLabel
    )
    $ValueKey = if ($Id -and $ViaGroupId) {
        "$Type`:$Id`:group:$ViaGroupId"
    } elseif ($Id) {
        "$Type`:$Id"
    } elseif ($Token) {
        "$Type`:$Token"
    } else {
        $Type
    }
    $Reason = @{
        type  = $Type
        value = $ValueKey
        label = $Label
    }
    if ($Id) { $Reason.id = $Id }
    if ($Transitive) { $Reason.transitive = $true }
    if ($ViaGroupId) {
        $Reason.viaGroupId = $ViaGroupId
        if ($ViaGroupLabel) { $Reason.viaGroupLabel = $ViaGroupLabel }
    }
    return $Reason
}

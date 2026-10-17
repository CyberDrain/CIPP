# Fetch permissions for a buffer of shared delta items and append their rows to $RowsOut.
# Failed batch responses are counted into $DropCounter: a full scan that lost reads must not
# prune the unread items' still-valid rows afterwards.
function Add-CIPPSharingRows {
    <#
    .NOTES
        Permission: Graph | GET /drives/{id}/items/{id}/permissions | Application | Files.Read.All | Files.ReadWrite.All, Sites.Read.All, Sites.ReadWrite.All
    #>
    param($Buffer, $Drive, $Site, $InternalDomains, $TenantFilter, $PassId, $RowsOut, [ref]$DropCounter)
    if (@($Buffer).Count -eq 0) { return }
    $ItemByRequestId = @{}
    $RequestId = 0
    $PermissionRequests = foreach ($SharedItem in $Buffer) {
        $ItemByRequestId["$RequestId"] = $SharedItem
        @{
            id     = "$RequestId"
            method = 'GET'
            url    = "drives/$($Drive.id)/items/$($SharedItem.id)/permissions"
        }
        $RequestId++
    }
    $PermissionResponses = New-GraphBulkRequest -tenantid $TenantFilter -Requests @($PermissionRequests) -asapp $true
    foreach ($Response in $PermissionResponses) {
        if ($Response.status -and $Response.status -ne 200) {
            if ($DropCounter) { $DropCounter.Value++ }
            continue
        }
        $DriveItem = $ItemByRequestId["$($Response.id)"]
        ConvertTo-CIPPSharingRow -Permissions @($Response.body.value) -DriveItem $DriveItem -Drive $Drive -Site $Site -InternalDomains $InternalDomains -TenantFilter $TenantFilter -PassId $PassId -RowsOut $RowsOut
    }
}

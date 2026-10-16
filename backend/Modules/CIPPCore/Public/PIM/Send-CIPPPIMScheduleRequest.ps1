function Send-CIPPPIMScheduleRequest {
    param($Request, $TenantFilter)
    $Json = ConvertTo-Json -InputObject $Request.Body -Depth 10 -Compress
    return New-GraphPOSTRequest -uri $Request.Uri -body $Json -tenantid $TenantFilter -AsApp $true
}

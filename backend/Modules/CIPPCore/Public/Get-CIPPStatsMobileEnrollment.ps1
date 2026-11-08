function Get-CIPPStatsMobileEnrollment {
    [CmdletBinding()]
    param()

    try {
        $MobileEnrollment = 0
        $Rows = Get-CIPPDbItem -TenantFilter allTenants -Type 'ManagedDevices' -ByTenant
        foreach ($Tenant in $Rows.Keys) {
            foreach ($Row in $Rows[$Tenant]) {
                if ([string]::IsNullOrWhiteSpace($Row.Data)) { continue }
                $Parsed = try { [CIPP.CippJson]::ConvertFromJson([string]$Row.Data, [string[]]@('operatingSystem')) } catch { $null }
                foreach ($Device in @($Parsed)) {
                    if ([string]$Device.operatingSystem -match 'iOS|iPadOS|Android') { $MobileEnrollment++ }
                }
            }
        }

        return $MobileEnrollment
    } catch {
        Write-LogMessage -API 'CIPPStatsTimer' -tenant $env:TenantID -message "Failed to calculate MobileEnrollment: $($_.Exception.Message)" -sev Warning
        return 0
    }
}

function Get-CIPPStatsMobileEnrollment {
    [CmdletBinding()]
    param()

    try {
        $MobileEnrollment = 0
        foreach ($Tenant in (Get-Tenants -IncludeErrors).defaultDomainName) {
            if ([string]::IsNullOrWhiteSpace($Tenant)) { continue }
            foreach ($Row in (Get-CIPPDbItem -Partition $Tenant -Type 'ManagedDevices')) {
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

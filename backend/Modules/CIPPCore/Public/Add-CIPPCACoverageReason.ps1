function Add-CIPPCACoverageReason {
    param (
        [hashtable]$Map,
        [string]$UserId,
        [hashtable]$Reason
    )
    if ([string]::IsNullOrWhiteSpace($UserId) -or $null -eq $Reason) { return }
    if (-not $Map.ContainsKey($UserId)) {
        $Map[$UserId] = [System.Collections.Generic.List[object]]::new()
    }
    $Existing = $Map[$UserId] | Where-Object { $_.value -eq $Reason.value }
    if ($Existing) { return }
    $Map[$UserId].Add([pscustomobject]$Reason) | Out-Null
}

function Get-CIPPBecMailActivity {
    <#
    .SYNOPSIS
        Counts the investigated user's mailbox activity from the unified audit log, bucketed by client IP and application.
    .DESCRIPTION
        Answers "what did they read, delete and send, and from where" without storing a single item:
        MailItemsAccessed, HardDelete, SoftDelete, MoveToDeletedItems and Send records attributed to the
        user, plus tenant-wide SendAs/SendOnBehalf records whose mailbox owner is the user, are reduced
        to counts per Operation x ClientIP x client application x access type with first/last seen
        times. Aggregated MailItemsAccessed records contribute their OperationCount. No subjects,
        folders or item ids are kept. MailItemsAccessed needs Purview Audit (Premium); when the log
        does not carry it the other operations still count.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserPrincipalName
        The investigated user.
    .PARAMETER StartDate
        Window start (UTC).
    .PARAMETER EndDate
        Window end (UTC).
    .PARAMETER Heuristics
        The BEC heuristics object (mailActivity section, caps).
    .PARAMETER Anchor
        Anchor mailbox for the EXO requests.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [Parameter(Mandatory = $true)][datetime]$StartDate,
        [Parameter(Mandatory = $true)][datetime]$EndDate,
        [Parameter(Mandatory = $true)]$Heuristics,
        [string]$Anchor
    )

    $UserOps = @($Heuristics.mailActivity.userOperations)
    $OwnerOps = @($Heuristics.mailActivity.mailboxOwnerOperations)
    $MaxPages = [int]($Heuristics.caps.mailActivityPages ?? 10)
    $GroupCap = [int]($Heuristics.caps.storedMailActivityGroups ?? 500)
    $HardDeleteThreshold = [int]($Heuristics.mailActivity.hardDeleteThreshold ?? 20)

    $Groups = @{}
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Complete = $true
    $Cap = $null
    $RecordCount = 0

    $Accumulate = {
        param($Record)
        $AD = $Record.AuditData
        if (-not $AD) { return }
        $Operation = [string]($AD.Operation ?? $Record.Operation)
        $ClientIP = [string]($AD.ClientIP ?? $AD.ClientIPAddress)
        $ClientInfo = [string]($AD.ClientInfoString ?? $AD.ClientAppId ?? $AD.ClientApplication)
        if ($ClientInfo.Length -gt 120) { $ClientInfo = $ClientInfo.Substring(0, 120) + '...' }
        $AccessType = [string]$AD.MailAccessType
        $Actor = [string]$AD.UserId
        $Owner = [string]($AD.MailboxOwnerUPN ?? $Actor)
        $Key = "$Operation|$ClientIP|$ClientInfo|$AccessType|$Actor|$Owner"
        $Count = if ($AD.OperationCount) { [int]$AD.OperationCount } else { 1 }
        $When = try { ([datetime]$AD.CreationTime).ToUniversalTime() } catch { $null }
        if (-not $Groups.ContainsKey($Key)) {
            $Groups[$Key] = [pscustomobject]@{
                Operation        = $Operation
                ClientIP         = $ClientIP
                ClientInfoString = $ClientInfo
                MailAccessType   = $AccessType
                LogonType        = $AD.LogonType
                Actor            = $Actor
                MailboxOwner     = $Owner
                Count            = 0
                Records          = 0
                FirstSeen        = $When
                LastSeen         = $When
            }
        }
        $Group = $Groups[$Key]
        $Group.Count += $Count
        $Group.Records += 1
        if ($When) {
            if (-not $Group.FirstSeen -or $When -lt $Group.FirstSeen) { $Group.FirstSeen = $When }
            if (-not $Group.LastSeen -or $When -gt $Group.LastSeen) { $Group.LastSeen = $When }
        }
    }

    if ($UserOps.Count -gt 0) {
        try {
            $Search = Search-CIPPBecAuditLog -TenantFilter $TenantFilter -StartDate $StartDate -EndDate $EndDate -Operations $UserOps -UserIds @($UserPrincipalName) -Anchor $Anchor -MaxPages $MaxPages
            foreach ($Record in $Search.Records) { & $Accumulate $Record; $RecordCount++ }
            if (-not $Search.Complete) { $Complete = $false; $Cap = $Search.Cap }
        } catch {
            $Errors.Add("user activity search: $((Get-NormalizedError -message $_.Exception.Message))")
        }
    }
    if ($OwnerOps.Count -gt 0) {
        try {
            $Search = Search-CIPPBecAuditLog -TenantFilter $TenantFilter -StartDate $StartDate -EndDate $EndDate -Operations $OwnerOps -Anchor $Anchor -MaxPages $MaxPages
            foreach ($Record in $Search.Records) {
                $AD = $Record.AuditData
                if (-not $AD) { continue }
                if ($AD.MailboxOwnerUPN -ne $UserPrincipalName -and $AD.UserId -ne $UserPrincipalName) { continue }
                & $Accumulate $Record
                $RecordCount++
            }
            if (-not $Search.Complete) { $Complete = $false; $Cap = $Search.Cap }
        } catch {
            $Errors.Add("send-as search: $((Get-NormalizedError -message $_.Exception.Message))")
        }
    }

    $Rows = @($Groups.Values | ForEach-Object {
            $_.FirstSeen = if ($_.FirstSeen) { $_.FirstSeen.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
            $_.LastSeen = if ($_.LastSeen) { $_.LastSeen.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
            $_
        } | Sort-Object -Property Count -Descending)

    $ByOperation = @{}
    foreach ($Row in $Rows) { $ByOperation[$Row.Operation] = [int]($ByOperation[$Row.Operation] ?? 0) + $Row.Count }
    $Summary = [pscustomobject]@{
        Records                = $RecordCount
        ByOperation            = [pscustomobject]$ByOperation
        MailItemsAccessedCount = [int]($ByOperation['MailItemsAccessed'] ?? 0)
        HardDeleteCount        = [int]($ByOperation['HardDelete'] ?? 0)
        SoftDeleteCount        = [int]($ByOperation['SoftDelete'] ?? 0)
        SendCount              = [int]($ByOperation['Send'] ?? 0)
        HardDeleteThreshold    = $HardDeleteThreshold
        HardDeleteExceeded     = ([int]($ByOperation['HardDelete'] ?? 0) -ge $HardDeleteThreshold)
        DistinctClientIPs      = @($Rows.ClientIP | Where-Object { $_ } | Select-Object -Unique).Count
        SendAsByOthersCount    = [int](@($Rows | Where-Object { $_.Operation -in $OwnerOps -and $_.MailboxOwner -eq $UserPrincipalName -and $_.Actor -ne $UserPrincipalName } | Measure-Object -Property Count -Sum).Sum)
    }

    $Capped = $Rows.Count -gt $GroupCap
    $Result = New-CIPPBecCollectorResult -Data @($Rows | Select-Object -First $GroupCap) -Complete ($Complete -and -not $Capped -and $Errors.Count -eq 0) -Cap ($(if ($Cap) { $Cap } elseif ($Capped) { "$GroupCap stored groups" } else { $null })) -Error ($(if ($Errors.Count -gt 0) { $Errors -join '; ' } else { $null })) -Count $Rows.Count
    $Result | Add-Member -NotePropertyName 'Summary' -NotePropertyValue $Summary -Force
    return $Result
}

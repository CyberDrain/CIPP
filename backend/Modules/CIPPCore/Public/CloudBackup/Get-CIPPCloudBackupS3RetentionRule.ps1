function Get-CIPPCloudBackupS3RetentionRule {
    <#
    .SYNOPSIS
        Reads a lifecycle rule by ID from an S3 cloud backup destination; returns { Prefix; Days; Mode } or $null.
    .DESCRIPTION
        Days is $null when the rule is disabled or has no expiration days, so a caller comparing it rewrites the rule.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Destination,
        [Parameter(Mandatory)][string]$RuleName
    )

    try {
        $Config = (Invoke-CIPPS3Request -Destination $Destination -Method GET -Query @{ lifecycle = '' }).Xml
    } catch {
        if ($_.Exception.Data['S3ErrorCode'] -eq 'NoSuchLifecycleConfiguration') { return $null }
        throw
    }
    if (-not $Config) { return $null }

    foreach ($Rule in $Config.DocumentElement.ChildNodes) {
        if ($Rule.LocalName -ne 'Rule' -or $Rule['ID'].InnerText -cne $RuleName) { continue }
        # The XML adapter would return XmlNode.Prefix (the namespace prefix), so read child elements by indexer
        $Filter = $Rule['Filter']
        $PrefixNode = if ($Filter -and $Filter['Prefix']) { $Filter['Prefix'] } elseif ($Filter -and $Filter['And']) { $Filter['And']['Prefix'] } else { $Rule['Prefix'] }
        $Versioned = $null -ne $Rule['NoncurrentVersionExpiration']
        $DaysNode = if ($Versioned) { $Rule['NoncurrentVersionExpiration']['NoncurrentDays'] } elseif ($Rule['Expiration']) { $Rule['Expiration']['Days'] }
        return [pscustomobject]@{
            Prefix = if ($PrefixNode) { $PrefixNode.InnerText } else { '' }
            Days   = if ($DaysNode -and $Rule['Status'].InnerText -eq 'Enabled') { [int]$DaysNode.InnerText } else { $null }
            Mode   = if ($Versioned) { 'Versioned' } else { 'Expire' }
        }
    }
    $null
}

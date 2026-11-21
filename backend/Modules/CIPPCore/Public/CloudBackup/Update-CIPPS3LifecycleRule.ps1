function Update-CIPPS3LifecycleRule {
    <#
    .SYNOPSIS
        Replaces or removes one lifecycle rule on an S3 bucket, keeping every other rule.
    .DESCRIPTION
        Reads the bucket lifecycle configuration, drops the rule with ID -RuleName, adds a rule for -Prefix when -Days is
        given (see Set-CIPPCloudBackupS3RetentionRule for -Mode), and writes the configuration back (or deletes it when no
        rules remain).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Destination,
        [Parameter(Mandatory)][string]$RuleName,
        [string]$Prefix,
        [int]$Days,
        [ValidateSet('Expire', 'Versioned')][string]$Mode = 'Expire'
    )

    $Existing = $null
    $MinimumObjectSize = $null
    try {
        $Response = Invoke-CIPPS3Request -Destination $Destination -Method GET -Query @{ lifecycle = '' }
        $Existing = $Response.Xml
        $MinimumObjectSize = $Response.Headers['x-amz-transition-default-minimum-object-size']
    } catch {
        if ($_.Exception.Data['S3ErrorCode'] -ne 'NoSuchLifecycleConfiguration') { throw }
    }

    $Namespace = if ($Existing -and $Existing.DocumentElement.NamespaceURI) { $Existing.DocumentElement.NamespaceURI } else { 'http://s3.amazonaws.com/doc/2006-03-01/' }
    $Document = [xml]::new()
    $Root = $Document.AppendChild($Document.CreateElement('LifecycleConfiguration', $Namespace))
    $Removed = $false
    $LegacyPrefix = $false
    if ($Existing) {
        foreach ($Rule in $Existing.DocumentElement.ChildNodes) {
            if ($Rule.LocalName -ne 'Rule') { continue }
            if ($Rule['ID'] -and $Rule['ID'].InnerText -ceq $RuleName) { $Removed = $true; continue }
            if ($Rule['Prefix']) { $LegacyPrefix = $true }
            $null = $Root.AppendChild($Document.ImportNode($Rule, $true))
        }
    }

    if ($PSBoundParameters.ContainsKey('Days')) {
        $NewRule = $Root.AppendChild($Document.CreateElement('Rule', $Namespace))
        $NewRule.AppendChild($Document.CreateElement('ID', $Namespace)).InnerText = $RuleName
        # A configuration can't mix the deprecated rule-level Prefix with Filter
        if ($LegacyPrefix) {
            $NewRule.AppendChild($Document.CreateElement('Prefix', $Namespace)).InnerText = $Prefix
        } else {
            $Filter = $NewRule.AppendChild($Document.CreateElement('Filter', $Namespace))
            $Filter.AppendChild($Document.CreateElement('Prefix', $Namespace)).InnerText = $Prefix
        }
        $NewRule.AppendChild($Document.CreateElement('Status', $Namespace)).InnerText = 'Enabled'
        $Expiration = $NewRule.AppendChild($Document.CreateElement('Expiration', $Namespace))
        if ($Mode -eq 'Versioned') {
            $Expiration.AppendChild($Document.CreateElement('ExpiredObjectDeleteMarker', $Namespace)).InnerText = 'true'
            $Noncurrent = $NewRule.AppendChild($Document.CreateElement('NoncurrentVersionExpiration', $Namespace))
            $Noncurrent.AppendChild($Document.CreateElement('NoncurrentDays', $Namespace)).InnerText = [string]$Days
            $Abort = $NewRule.AppendChild($Document.CreateElement('AbortIncompleteMultipartUpload', $Namespace))
            $Abort.AppendChild($Document.CreateElement('DaysAfterInitiation', $Namespace)).InnerText = '7'
        } else {
            $Expiration.AppendChild($Document.CreateElement('Days', $Namespace)).InnerText = [string]$Days
        }
    } elseif (-not $Removed) {
        return
    }

    if (-not $PSCmdlet.ShouldProcess($RuleName, 'Update S3 lifecycle configuration')) { return }
    if (-not $Root.HasChildNodes) {
        $null = Invoke-CIPPS3Request -Destination $Destination -Method DELETE -Query @{ lifecycle = '' }
        return
    }

    $Body = [System.Text.Encoding]::UTF8.GetBytes($Document.OuterXml)
    $Headers = @{
        'Content-Type' = 'application/xml'
        'Content-MD5'  = [Convert]::ToBase64String([System.Security.Cryptography.MD5]::HashData($Body))
    }
    # AWS resets this bucket setting to its default on a PUT that omits it
    if ($MinimumObjectSize) { $Headers['x-amz-transition-default-minimum-object-size'] = $MinimumObjectSize }
    $null = Invoke-CIPPS3Request -Destination $Destination -Method PUT -Query @{ lifecycle = '' } -Body $Body -Headers $Headers
}

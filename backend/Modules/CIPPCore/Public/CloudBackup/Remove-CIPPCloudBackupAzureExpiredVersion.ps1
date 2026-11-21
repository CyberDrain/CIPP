function Remove-CIPPCloudBackupAzureExpiredVersion {
    <#
    .SYNOPSIS
        Deletes previous blob versions under a prefix that were replaced or deleted more than -Days ago, and returns { Examined; Deleted; Failed; Skipped; Errors }.
    .DESCRIPTION
        A previous version ages from the creation of the version that replaced it. A cippdeletedat marker version (written
        by Remove-CIPPCloudBackupAzureObject) ages from its own creation, the deletion time. The newest version of a blob
        deleted without a marker has no known deletion time and is kept. Stops at the first permission failure. A version
        still under an immutability policy is counted in Skipped, together with the newer versions of that blob.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$Prefix,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 36500)]
        [int]$Days,

        [ValidateRange(1, 1000000)]
        [int]$MaxDeletes = 1000
    )

    $Cutoff = [datetime]::UtcNow.AddDays(-$Days)
    $Styles = [System.Globalization.DateTimeStyles]'AdjustToUniversal, AssumeUniversal'
    $Examined = 0
    $Deleted = 0
    $Failed = 0
    $Skipped = 0
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Stop = $false

    $GroupKey = $null
    $Group = [System.Collections.Generic.List[object]]::new()
    $Marker = $null
    $Done = $false
    while (-not $Done -and -not $Stop) {
        $Query = [ordered]@{ restype = 'container'; comp = 'list'; include = 'versions,metadata'; maxresults = 5000; prefix = $Prefix }
        if ($Marker) { $Query.marker = $Marker }
        $Response = Invoke-CIPPCloudBackupAzureBlobRequest -Destination $Destination -Method 'GET' -Query $Query
        $Xml = [xml]([System.Text.Encoding]::UTF8.GetString($Response.Body).TrimStart([char]0xFEFF))
        $Marker = $Xml.SelectSingleNode('/EnumerationResults/NextMarker').InnerText
        $Done = -not $Marker
        $Blobs = @($Xml.SelectNodes('/EnumerationResults/Blobs/Blob'))

        # A blob's versions are listed together but can continue on the next page, so a group is processed once the
        # next blob starts or the listing ends.
        for ($i = 0; $i -le $Blobs.Count; $i++) {
            $Blob = if ($i -lt $Blobs.Count) { $Blobs[$i] }
            $Name = if ($Blob) { $Blob.SelectSingleNode('Name').InnerText }
            if ($Blob -and $Name -ceq $GroupKey) {
                $Group.Add($Blob)
                continue
            }
            if (-not $Blob -and -not $Done) { break }

            if ($Group.Count -gt 0) {
                $Ids = [string[]]::new($Group.Count)
                $Items = $Group.ToArray()
                for ($j = 0; $j -lt $Items.Count; $j++) {
                    $VersionNode = $Items[$j].SelectSingleNode('VersionId')
                    $Ids[$j] = if ($VersionNode) { $VersionNode.InnerText } else { '' }
                }
                # The non-generic overload: PowerShell binds the generic one to a converted copy of $Items and leaves it unsorted.
                [System.Array]::Sort([System.Array]$Ids, [System.Array]$Items, [System.Collections.IComparer][System.StringComparer]::Ordinal)
                $Examined += $Items.Count

                for ($j = 0; $j -lt $Items.Count; $j++) {
                    if (-not $Ids[$j]) { continue }
                    $Current = $Items[$j].SelectSingleNode('IsCurrentVersion')
                    if ($Current -and $Current.InnerText -eq 'true') { continue }

                    $ReplacedAt = if ($j + 1 -lt $Items.Count) {
                        [datetime]::Parse($Ids[$j + 1], [cultureinfo]::InvariantCulture, $Styles)
                    } elseif ($Items[$j].SelectSingleNode('Metadata/cippdeletedat')) {
                        [datetime]::Parse($Ids[$j], [cultureinfo]::InvariantCulture, $Styles)
                    }
                    if ($null -eq $ReplacedAt -or $ReplacedAt -ge $Cutoff) { continue }
                    if ($Deleted + $Failed -ge $MaxDeletes) { $Stop = $true; break }
                    if (-not $PSCmdlet.ShouldProcess("$GroupKey ($($Ids[$j]))", 'Delete expired version')) { continue }

                    try {
                        Remove-CIPPCloudBackupAzureObject -Destination $Destination -Key $GroupKey -VersionId $Ids[$j] -Confirm:$false
                        $Deleted++
                    } catch {
                        if ("$($_.Exception.Data['ErrorCode'])" -like 'BlobImmutable*') {
                            $Skipped++
                            break
                        }
                        $Failed++
                        if ($Errors.Count -lt 20) { $Errors.Add("$($GroupKey): $($_.Exception.Message)") }
                        if ($_.Exception.Data['StatusCode'] -eq 403) { $Stop = $true }
                        break
                    }
                }
            }
            if ($Stop -or -not $Blob) { break }
            $GroupKey = $Name
            $Group.Clear()
            $Group.Add($Blob)
        }
    }

    [pscustomobject]@{
        Examined = $Examined
        Deleted  = $Deleted
        Failed   = $Failed
        Skipped  = $Skipped
        Errors   = @($Errors)
    }
}

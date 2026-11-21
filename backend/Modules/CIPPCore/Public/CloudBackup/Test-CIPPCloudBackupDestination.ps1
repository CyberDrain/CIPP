function Test-CIPPCloudBackupDestination {
    <#
    .SYNOPSIS
        Checks that CIPP can write, read and delete objects and read the lifecycle configuration on a cloud backup destination.
    .DESCRIPTION
        On Azure the probe's versions are then deleted by version id, which also checks the Storage Blob Data Owner role
        that version pruning needs; on S3 VersionDelete follows Delete. A version delete refused only because the version is
        still immutable also counts, since Azure checks the role first; those probe versions stay until their period ends. ContentReady is true when the checks pass,
        versioning is Enabled and VersionDelete works, which content backup policies require.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination
    )

    $Errors = [System.Collections.Generic.List[string]]::new()
    $Write = $false
    $Read = $false
    $Delete = $false
    $Lifecycle = $false
    $VersionDelete = $false
    $Versioning = 'Unknown'

    $Key = ".cipp-test-$([guid]::NewGuid())"
    $Content = [System.Text.Encoding]::UTF8.GetBytes("CIPP cloud backup connection test $([datetime]::UtcNow.ToString('o'))")

    try {
        $null = Set-CIPPCloudBackupObject -Destination $Destination -Key $Key -Body $Content -ContentType 'text/plain'
        $Write = $true
    } catch {
        $Errors.Add("Write: $($_.Exception.Message)")
    }

    if ($Write) {
        try {
            $Object = Get-CIPPCloudBackupObject -Destination $Destination -Key $Key
            if ($Object -and [System.Convert]::ToBase64String([byte[]]$Object.Body) -eq [System.Convert]::ToBase64String($Content)) {
                $Read = $true
            } else {
                $Errors.Add('Read: the test object came back missing or different from what was written.')
            }
        } catch {
            $Errors.Add("Read: $($_.Exception.Message)")
        }
        try {
            Remove-CIPPCloudBackupObject -Destination $Destination -Key $Key
            $Delete = $true
        } catch {
            $Errors.Add("Delete: $($_.Exception.Message)")
        }
    }

    if ($Delete -and $Destination.Provider -eq 'AzureBlob') {
        try {
            foreach ($Version in @(Get-CIPPCloudBackupObjectVersionList -Destination $Destination -Prefix $Key)) {
                if ($Version.Key -ceq $Key -and $Version.VersionId) {
                    Remove-CIPPCloudBackupObject -Destination $Destination -Key $Key -VersionId $Version.VersionId
                }
            }
            $VersionDelete = $true
        } catch {
            if ("$($_.Exception.Data['ErrorCode'])" -like 'BlobImmutable*') {
                $VersionDelete = $true
            } else {
                $Errors.Add("Version delete: $($_.Exception.Message)")
            }
        }
    } else {
        $VersionDelete = $Delete
    }

    try {
        $null = Get-CIPPCloudBackupRetentionRule -Destination $Destination -RuleName 'cipp-connection-test'
        $Lifecycle = $true
    } catch {
        $Errors.Add("Lifecycle: $($_.Exception.Message)")
    }

    try {
        $Versioning = Get-CIPPCloudBackupVersioning -Destination $Destination
    } catch {
        $Errors.Add("Versioning: $($_.Exception.Message)")
    }

    $Passed = $Write -and $Read -and $Delete -and $Lifecycle
    return [pscustomobject]@{
        Write         = $Write
        Read          = $Read
        Delete        = $Delete
        Lifecycle     = $Lifecycle
        Versioning    = $Versioning
        VersionDelete = $VersionDelete
        Passed        = $Passed
        ContentReady  = $Passed -and $Versioning -eq 'Enabled' -and $VersionDelete
        Errors        = @($Errors)
    }
}

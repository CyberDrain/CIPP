function Invoke-CIPPCloudBackupDriveStep {
    <#
    .SYNOPSIS
        Backs up one delta page (or one chunk of retried files) of a set of drives.
    .DESCRIPTION
        Shared by the OneDrive and SharePoint workloads. Pass -Drives at the start of a run to refresh the drive set;
        omit it to continue the run held in -State.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context,
        $State,
        # @{ Id; Name; WebUrl } per drive
        $Drives
    )

    $PageSize = 200
    $RetryChunk = 20
    $MaxFailed = 100
    $DeltaSelect = 'id,name,size,file,folder,package,deleted,root,parentReference,lastModifiedDateTime,eTag,webUrl,remoteItem'
    $Tenant = $Context.TenantFilter

    $DriveStates = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($Saved in @($State.Drives)) {
        if (-not $Saved.Id) { continue }
        $DriveStates.Add(@{
                Id       = [string]$Saved.Id
                Name     = [string]$Saved.Name
                WebUrl   = [string]$Saved.WebUrl
                Link     = [string]$Saved.Link
                Complete = [bool]$Saved.Complete
                Retry    = @(foreach ($Id in @($Saved.Retry)) { if ($Id) { [string]$Id } })
                Failed   = @(foreach ($Id in @($Saved.Failed)) { if ($Id) { [string]$Id } })
            })
    }
    if ($null -ne $Drives) {
        $Previous = @{}
        foreach ($DriveState in $DriveStates) { $Previous[$DriveState.Id] = $DriveState }
        $DriveStates = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($Drive in @($Drives)) {
            if (-not $Drive.Id) { continue }
            $Old = $Previous[[string]$Drive.Id]
            $Pending = [System.Collections.Generic.HashSet[string]]::new()
            if ($Old) {
                foreach ($Id in $Old.Retry) { $null = $Pending.Add($Id) }
                foreach ($Id in $Old.Failed) { $null = $Pending.Add($Id) }
            }
            $DriveStates.Add(@{
                    Id       = [string]$Drive.Id
                    Name     = [string]$Drive.Name
                    WebUrl   = [string]$Drive.WebUrl
                    Link     = if ($Old) { $Old.Link } else { '' }
                    Complete = $false
                    Retry    = @($Pending)
                    Failed   = @()
                })
        }
    }

    $Warnings = [System.Collections.Generic.List[string]]::new()
    $IndexEntries = [System.Collections.Generic.List[object]]::new()
    $Items = 0
    $Bytes = [int64]0
    $Deleted = 0

    $Current = $null
    foreach ($DriveState in $DriveStates) {
        if (-not $DriveState.Complete) { $Current = $DriveState; break }
    }

    if ($Current) {
        $DriveId = $Current.Id
        $FullDeltaUri = "https://graph.microsoft.com/v1.0/drives/$DriveId/root/delta?`$select=$DeltaSelect&`$top=$PageSize"
        $PageItems = @()
        $NextLink = $null
        $ReachedEnd = $false
        $NewFailures = [System.Collections.Generic.List[string]]::new()
        $IsRetry = $Current.Retry.Count -gt 0

        if ($IsRetry) {
            $Take = [Math]::Min($RetryChunk, $Current.Retry.Count)
            $RetryIds = @($Current.Retry[0..($Take - 1)])
            $Current.Retry = if ($Current.Retry.Count -gt $Take) { @($Current.Retry[$Take..($Current.Retry.Count - 1)]) } else { @() }
            $Requests = foreach ($Id in $RetryIds) {
                @{ id = $Id; method = 'GET'; url = "drives/$DriveId/items/$Id`?`$select=$DeltaSelect" }
            }
            $Results = @(New-GraphBulkRequest -tenantid $Tenant -asapp $true -Version 'v1.0' -Requests @($Requests))
            $ResultById = @{}
            foreach ($Result in $Results) { $ResultById[[string]$Result.id] = $Result }
            $PageItems = foreach ($Id in $RetryIds) {
                $Result = $ResultById[$Id]
                if ($Result.status -eq 200) {
                    $Result.body
                } elseif ($Result.status -ne 404) {
                    $NewFailures.Add($Id)
                    $Warnings.Add("Could not read file $Id in $($Current.Name) to retry it: $($Result.body.error.message ?? $Result.status)")
                }
            }
        } else {
            $Uri = if ($Current.Link) { $Current.Link } else { $FullDeltaUri }
            try {
                $Page = New-GraphGetRequest -uri $Uri -tenantid $Tenant -asapp $true -noPagination $true -SkipValueExtraction
            } catch {
                $Message = $_.Exception.Message
                if ($Uri -ne $FullDeltaUri -and $Message -match 'resync|SyncStateNotFound|Gone|410') {
                    $Current.Link = ''
                    $Warnings.Add("The change position for $($Current.Name) expired; it is being read again in full.")
                    $Page = $null
                } elseif ($Message -match 'Access to this site has been blocked|itemNotFound|ResourceNotFound') {
                    $Current.Complete = $true
                    $Warnings.Add("$($Current.Name) could not be read and was skipped this run: $Message")
                    $Page = $null
                } else {
                    throw
                }
            }
            if ($Page) {
                $PageItems = @($Page.value)
                $ReachedEnd = [bool]$Page.'@odata.deltaLink'
                $NextLink = if ($ReachedEnd) { [string]$Page.'@odata.deltaLink' } else { [string]$Page.'@odata.nextLink' }
            }
        }

        $ParentIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($Item in $PageItems) {
            if ($Item.parentReference.id -and -not $Item.deleted -and -not $Item.parentReference.path) { $null = $ParentIds.Add([string]$Item.parentReference.id) }
        }
        $PathById = @{}
        if ($ParentIds.Count -gt 0) {
            $Requests = foreach ($Id in $ParentIds) {
                @{ id = $Id; method = 'GET'; url = "drives/$DriveId/items/$Id`?`$select=id,name,root,parentReference" }
            }
            try {
                foreach ($Result in @(New-GraphBulkRequest -tenantid $Tenant -asapp $true -Version 'v1.0' -Requests @($Requests))) {
                    if ($Result.status -ne 200) { continue }
                    $Folder = $Result.body
                    $PathById[[string]$Result.id] = if ($Folder.root) { '/' } else { "$(([string]$Folder.parentReference.path) -replace '^.*?root:', '')/$($Folder.name)" }
                }
            } catch {
                $Warnings.Add("Folder paths in $($Current.Name) could not be read: $($_.Exception.Message)")
            }
        }

        $Client = $null
        $OnStop = $null
        try {
            foreach ($Item in $PageItems) {
                if ($null -eq $Item -or $Item.root -or $Item.remoteItem) { continue }
                $ItemId = [string]$Item.id
                $Key = "items/$DriveId/$ItemId"
                $ParentPath = if ($Item.parentReference.path) { ([string]$Item.parentReference.path) -replace '^.*?root:', '' } else { $PathById[[string]$Item.parentReference.id] }
                if ($ParentPath -eq '') { $ParentPath = '/' }
                $Extra = @{
                    driveId   = $DriveId
                    driveName = $Current.Name
                    parentId  = $Item.parentReference.id
                    eTag      = $Item.eTag
                    webUrl    = $Item.webUrl
                }

                if ($Item.deleted) {
                    $Type = if ($Item.folder -or $Item.package) { 'folder' } else { 'file' }
                    if ($Type -eq 'file') {
                        try {
                            $null = Remove-CIPPCloudBackupItem -Context $Context -ItemKey $Key
                        } catch {
                            $Warnings.Add("Could not mark deleted file $ItemId in $($Current.Name) as deleted: $($_.Exception.Message)")
                            continue
                        }
                    }
                    $Deleted++
                    $IndexEntries.Add([pscustomobject]@{ k = $Key; p = $ParentPath; n = $Item.name; t = $Type; s = $null; m = $Item.lastModifiedDateTime; v = $null; d = $true; x = $Extra })
                    continue
                }

                if ($Item.folder -or $Item.package) {
                    if ($Item.package) { $Extra.package = $Item.package.type }
                    $IndexEntries.Add([pscustomobject]@{ k = $Key; p = $ParentPath; n = $Item.name; t = 'folder'; s = $Item.size; m = $Item.lastModifiedDateTime; v = $null; d = $false; x = $Extra })
                    continue
                }

                if (-not $Item.file) { continue }

                $Response = $null
                $Written = $null
                try {
                    $Meta = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/drives/$DriveId/items/$ItemId`?`$select=id,content.downloadUrl" -tenantid $Tenant -asapp $true
                    $DownloadUrl = [string]$Meta.'@microsoft.graph.downloadUrl'
                    if (-not $DownloadUrl) { throw 'Graph returned no download URL.' }
                    if (-not $Client) {
                        $Client = [System.Net.Http.HttpClient]::new()
                        $Client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
                        $StopToken = $PSCmdlet.PipelineStopToken
                        # Disposing the client aborts a stalled download when the worker stops the pipeline.
                        $OnStop = if ($StopToken) { $StopToken.Register([Action]$Client.Dispose) }
                    }
                    # The pre-authenticated download URL must not receive CIPP's bearer token:
                    # https://learn.microsoft.com/graph/api/driveitem-get-content
                    $Response = $Client.GetAsync($DownloadUrl, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
                    if (-not $Response.IsSuccessStatusCode) { throw "The download returned status $([int]$Response.StatusCode)." }
                    $Body = $Response.Content.ReadAsStream()
                    try {
                        $Written = Write-CIPPCloudBackupItem -Context $Context -ItemKey $Key -Stream $Body -ContentType ([string]($Item.file.mimeType ?? 'application/octet-stream'))
                    } finally {
                        $Body.Dispose()
                    }
                } catch {
                    $NewFailures.Add($ItemId)
                    $Warnings.Add("Could not back up $ParentPath/$($Item.name) in $($Current.Name); it will be retried next run: $($_.Exception.Message)")
                    continue
                } finally {
                    if ($Response) { $Response.Dispose() }
                }

                $Items++
                $Bytes = $Bytes + [int64]$Written.Bytes
                $Hashes = $Item.file.hashes
                $Extra.hash = $Hashes.quickXorHash ?? $Hashes.sha256Hash ?? $Hashes.sha1Hash
                $Extra.mimeType = $Item.file.mimeType
                $IndexEntries.Add([pscustomobject]@{ k = $Key; p = $ParentPath; n = $Item.name; t = 'file'; s = [int64]$Written.Size; m = $Item.lastModifiedDateTime; v = $Written.VersionId; d = $false; x = $Extra })
            }
        } finally {
            if ($OnStop) { $OnStop.Dispose() }
            if ($Client) { $Client.Dispose() }
        }

        $Pending = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Current.Failed))
        foreach ($Id in $NewFailures) { $null = $Pending.Add($Id) }
        if (-not $IsRetry -and $Pending.Count -gt $MaxFailed) {
            $Current.Complete = $true
            $Warnings.Add("Too many files in $($Current.Name) failed; this part of the library is read again next run.")
        } else {
            $Current.Failed = @($Pending)
            if ($NextLink) { $Current.Link = $NextLink }
            if ($ReachedEnd) { $Current.Complete = $true }
        }
    }

    $Done = $true
    foreach ($DriveState in $DriveStates) {
        if (-not $DriveState.Complete) { $Done = $false; break }
    }

    [pscustomobject]@{
        State        = @{ RunId = $Context.RunId; Drives = @($DriveStates) }
        Done         = $Done
        Items        = $Items
        Bytes        = $Bytes
        Deleted      = $Deleted
        Warnings     = @($Warnings)
        IndexEntries = @($IndexEntries)
    }
}

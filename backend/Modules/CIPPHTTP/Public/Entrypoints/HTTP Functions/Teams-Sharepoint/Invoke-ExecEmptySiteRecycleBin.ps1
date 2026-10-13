function Invoke-ExecEmptySiteRecycleBin {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.SiteRecycleBin.ReadWrite
    .DESCRIPTION
        Permanently empty a site recycle bin (first stage, second stage, or both).
        Item ids are used only server-side; the response never includes file names.
        After bulk deletion, verifies by re-reading the bin and falls back to batched
        DeleteByIds when items remain. Returns accurate counts and bytes freed.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Body.TenantFilter
    $SiteUrl = $Request.Body.SiteUrl
    $Stage = [string]($Request.Body.Stage ?? 'Both')

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter is required.' } })
    }
    if ([string]::IsNullOrWhiteSpace($SiteUrl)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'SiteUrl is required.' } })
    }
    if ($Stage -notin @('First', 'Second', 'Both')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Invalid Stage '$Stage'. Valid values: First, Second, Both." }
            })
    }

    try {
        $RestContext = Resolve-CIPPSharePointRestContext -TenantFilter $TenantFilter -SiteUrl $SiteUrl
        $Scope = $RestContext.Scope
        $JsonAccept = $RestContext.Headers
        $BaseUri = $RestContext.BaseUri
        $Errors = [System.Collections.Generic.List[string]]::new()

        function Get-CIPPRecycleBinSnapshot {
            param(
                [ValidateSet('First', 'Second')]
                [string]$TargetStage
            )
            $StateFilter = if ($TargetStage -eq 'Second') { 2 } else { 1 }
            $Count = 0
            $Bytes = [int64]0
            $Items = @()
            $Skip = 0
            $PageSize = 500
            $Guard = 0
            while ($Guard -lt 100) {
                $Guard++
                $Uri = "$BaseUri/site/RecycleBin?`$select=Id,Size,ItemState&`$top=$PageSize&`$skip=$Skip&`$orderby=DeletedDate desc"
                $Page = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true -noPagination $true -SkipValueExtraction
                $PageItems = @($Page.value)
                if ($PageItems.Count -eq 0) { break }
                
                foreach ($Item in $PageItems) {
                    $State = 0
                    try { $State = [int]$Item.ItemState } catch { $State = 0 }
                    if ($State -eq $StateFilter) {
                        $Count++
                        $Size = 0
                        try { $Size = [int64][double]$Item.Size } catch { $Size = 0 }
                        $Bytes += $Size
                        $Items += $Item
                    }
                }
                
                $Skip += $PageSize
                if ($PageItems.Count -lt $PageSize) { break }
            }
            return @{
                Count = $Count
                Bytes = $Bytes
                Items = $Items
            }
        }

        function Invoke-CIPPRecycleDeleteAll {
            param([string]$Uri)
            try {
                $null = New-GraphPostRequest -uri $Uri -tenantid $TenantFilter -scope $Scope -type POST -body '{}' -contentType 'application/json;odata=nometadata' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                return $true
            } catch {
                return $false
            }
        }

        function Invoke-CIPPRecycleDeleteByIdsBatch {
            param(
                [array]$Items,
                [string]$StageName
            )
            $DeletedCount = 0
            $Ids = @($Items | ForEach-Object { [string]$_.Id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($Ids.Count -eq 0) { return 0 }

            for ($i = 0; $i -lt $Ids.Count; $i += 25) {
                $Chunk = @($Ids[$i..([Math]::Min($i + 24, $Ids.Count - 1))])
                $DeleteBody = ConvertTo-Json -Compress -Depth 5 -InputObject @{ ids = @($Chunk) }
                
                $RetryCount = 0
                $MaxRetries = 5
                $Success = $false
                
                while (-not $Success -and $RetryCount -lt $MaxRetries) {
                    try {
                        $null = New-GraphPostRequest -uri "$BaseUri/site/RecycleBin/DeleteByIds" -tenantid $TenantFilter -scope $Scope -type POST -body $DeleteBody -contentType 'application/json;odata=nometadata' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                        $DeletedCount += $Chunk.Count
                        $Success = $true
                    } catch {
                        $StatusCode = $_.Exception.Response.StatusCode.value__
                        if ($StatusCode -in @(429, 503)) {
                            $RetryAfter = 5
                            $RetryAfterHeader = $_.Exception.Response.Headers | Where-Object { $_.Key -eq 'Retry-After' } | Select-Object -First 1
                            if ($RetryAfterHeader) {
                                try { $RetryAfter = [int]$RetryAfterHeader.Value[0] } catch { $RetryAfter = 5 }
                            }
                            Start-Sleep -Seconds ([Math]::Min($RetryAfter, 60))
                            $RetryCount++
                        } else {
                            throw
                        }
                    }
                }
                
                if (-not $Success) {
                    throw "Failed to delete batch after $MaxRetries retries (throttled)"
                }
            }
            return $DeletedCount
        }

        function Invoke-CIPPEmptyStage {
            param(
                [ValidateSet('First', 'Second')]
                [string]$TargetStage
            )
            
            $Before = Get-CIPPRecycleBinSnapshot -TargetStage $TargetStage
            $BeforeCount = $Before.Count
            $BeforeBytes = $Before.Bytes
            
            if ($BeforeCount -eq 0) {
                return @{
                    Success        = $true
                    BeforeCount    = 0
                    BeforeBytes    = 0
                    DeletedCount   = 0
                    BytesFreed     = 0
                    RemainingCount = 0
                    RemainingBytes = 0
                    Error          = $null
                }
            }

            $BulkUris = if ($TargetStage -eq 'Second') {
                @(
                    "$BaseUri/site/RecycleBin/deleteAllSecondStageItems",
                    "$BaseUri/site/RecycleBin/deleteAll()"
                )
            } else {
                @(
                    "$BaseUri/web/RecycleBin/deleteAll()",
                    "$BaseUri/site/RecycleBin/deleteAll()"
                )
            }

            $BulkSuccess = $false
            foreach ($Uri in $BulkUris) {
                if (Invoke-CIPPRecycleDeleteAll -Uri $Uri) {
                    Start-Sleep -Seconds 2
                    $BulkSuccess = $true
                    break
                }
            }

            if (-not $BulkSuccess) {
                try {
                    $BatchDeleted = Invoke-CIPPRecycleDeleteByIdsBatch -Items $Before.Items -StageName $TargetStage
                } catch {
                    return @{
                        Success        = $false
                        BeforeCount    = $BeforeCount
                        BeforeBytes    = $BeforeBytes
                        DeletedCount   = 0
                        BytesFreed     = 0
                        RemainingCount = $BeforeCount
                        RemainingBytes = $BeforeBytes
                        Error          = $_.Exception.Message
                    }
                }
            }

            Start-Sleep -Seconds 2
            $After = Get-CIPPRecycleBinSnapshot -TargetStage $TargetStage
            $RemainingCount = $After.Count
            $RemainingBytes = $After.Bytes
            $DeletedCount = $BeforeCount - $RemainingCount
            $BytesFreed = $BeforeBytes - $RemainingBytes

            if ($RemainingCount -gt 0 -and $DeletedCount -eq 0) {
                try {
                    $BatchDeleted = Invoke-CIPPRecycleDeleteByIdsBatch -Items $After.Items -StageName $TargetStage
                    Start-Sleep -Seconds 2
                    $AfterBatch = Get-CIPPRecycleBinSnapshot -TargetStage $TargetStage
                    $RemainingCount = $AfterBatch.Count
                    $RemainingBytes = $AfterBatch.Bytes
                    $DeletedCount = $BeforeCount - $RemainingCount
                    $BytesFreed = $BeforeBytes - $RemainingBytes
                } catch {
                    return @{
                        Success        = $false
                        BeforeCount    = $BeforeCount
                        BeforeBytes    = $BeforeBytes
                        DeletedCount   = $DeletedCount
                        BytesFreed     = $BytesFreed
                        RemainingCount = $RemainingCount
                        RemainingBytes = $RemainingBytes
                        Error          = $_.Exception.Message
                    }
                }
            }

            return @{
                Success        = $RemainingCount -eq 0
                BeforeCount    = $BeforeCount
                BeforeBytes    = $BeforeBytes
                DeletedCount   = $DeletedCount
                BytesFreed     = $BytesFreed
                RemainingCount = $RemainingCount
                RemainingBytes = $RemainingBytes
                Error          = if ($RemainingCount -gt 0) { "Items remain after deletion (may be held by retention policy or legal hold)" } else { $null }
            }
        }

        $FirstResult = $null
        $SecondResult = $null

        if ($Stage -in @('First', 'Both')) {
            $FirstResult = Invoke-CIPPEmptyStage -TargetStage First
            if ($FirstResult.Error) {
                $Errors.Add("First stage: $($FirstResult.Error)")
            }
        }

        if ($Stage -in @('Second', 'Both')) {
            $SecondResult = Invoke-CIPPEmptyStage -TargetStage Second
            if ($SecondResult.Error) {
                $Errors.Add("Second stage: $($SecondResult.Error)")
            }
        }

        $TotalBefore = ($FirstResult?.BeforeCount ?? 0) + ($SecondResult?.BeforeCount ?? 0)
        $TotalDeleted = ($FirstResult?.DeletedCount ?? 0) + ($SecondResult?.DeletedCount ?? 0)
        $TotalRemaining = ($FirstResult?.RemainingCount ?? 0) + ($SecondResult?.RemainingCount ?? 0)
        $TotalBytesFreed = ($FirstResult?.BytesFreed ?? 0) + ($SecondResult?.BytesFreed ?? 0)

        $Body = @{
            Results = if ($TotalRemaining -eq 0) {
                "Successfully emptied recycle bin ($Stage) for $SiteUrl. Deleted $TotalDeleted items, freed $([Math]::Round($TotalBytesFreed / 1MB, 2)) MB."
            } elseif ($TotalDeleted -gt 0) {
                "Partially emptied recycle bin ($Stage) for $SiteUrl. Deleted $TotalDeleted of $TotalBefore items, $TotalRemaining items remain (may be held by retention policy or legal hold)."
            } else {
                "Failed to empty recycle bin ($Stage) for $SiteUrl. $TotalRemaining items could not be deleted (may be held by retention policy or legal hold)."
            }
            itemsBefore      = $TotalBefore
            itemsDeleted     = $TotalDeleted
            itemsRemaining   = $TotalRemaining
            bytesFreed       = $TotalBytesFreed
            firstStage       = if ($FirstResult) {
                @{
                    beforeCount    = $FirstResult.BeforeCount
                    beforeBytes    = $FirstResult.BeforeBytes
                    deletedCount   = $FirstResult.DeletedCount
                    bytesFreed     = $FirstResult.BytesFreed
                    remainingCount = $FirstResult.RemainingCount
                    remainingBytes = $FirstResult.RemainingBytes
                }
            } else { $null }
            secondStage      = if ($SecondResult) {
                @{
                    beforeCount    = $SecondResult.BeforeCount
                    beforeBytes    = $SecondResult.BeforeBytes
                    deletedCount   = $SecondResult.DeletedCount
                    bytesFreed     = $SecondResult.BytesFreed
                    remainingCount = $SecondResult.RemainingCount
                    remainingBytes = $SecondResult.RemainingBytes
                }
            } else { $null }
        }

        if ($Errors.Count -gt 0) {
            $Body.Results += " Errors: $($Errors -join '; ')"
        }

        $LogSev = if ($TotalRemaining -eq 0) { 'Info' } elseif ($TotalDeleted -gt 0) { 'Warn' } else { 'Error' }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Body.Results -sev $LogSev

        $StatusCode = if ($TotalRemaining -eq 0) {
            [HttpStatusCode]::OK
        } elseif ($TotalDeleted -gt 0) {
            [HttpStatusCode]::OK
        } else {
            Get-CippBulkStatusCode -Total 1 -Failed 1
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to empty recycle bin on $($SiteUrl): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ Results = $Results }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

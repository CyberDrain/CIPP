function Restore-CIPPCloudBackupDriveFile {
    <#
    .SYNOPSIS
        Streams one backed-up file version from storage into a drive folder through a Graph upload session and returns { Id; Name; Bytes }.
    .DESCRIPTION
        Reads the stored object in 8 MiB ranges, decrypts CIPPENC2 data as it arrives and uploads it in 10 MiB
        fragments, so memory stays bounded whatever the file size. A name conflict that Graph refuses throws an
        exception with Data['Conflict'] set; any other failure cancels the upload session.
    .FUNCTIONALITY
        Internal
    .LINK
        https://learn.microsoft.com/graph/api/driveitem-createuploadsession
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context,

        [Parameter(Mandatory = $true)]
        $Entry,

        [Parameter(Mandatory = $true)]
        [string]$DriveId,

        [Parameter(Mandatory = $true)]
        [string]$ParentId,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [ValidateSet('fail', 'replace', 'rename')]
        [string]$ConflictBehavior = 'fail',

        [Parameter(Mandatory = $true)]
        [System.Net.Http.HttpClient]$Client
    )

    # Fragments must be multiples of 320 KiB and under 60 MiB.
    $FragmentSize = 32 * 320KB
    $WindowSize = 8MB
    $Tenant = $Context.TenantFilter
    $StoredKey = "$($Context.OwnerPrefix)$(([string]$Entry.Key).TrimStart('/'))"
    $ItemUri = "https://graph.microsoft.com/v1.0/drives/$DriveId/items/$($ParentId):/$([uri]::EscapeDataString($Name)):"

    $Item = @{ '@microsoft.graph.conflictBehavior' = $ConflictBehavior }
    $Modified = [datetime]::MinValue
    if ($Entry.Modified -is [datetime]) {
        $Modified = $Entry.Modified
    } elseif ($Entry.Modified -and -not [datetime]::TryParse([string]$Entry.Modified, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$Modified)) {
        $Modified = [datetime]::MinValue
    }
    if ($Modified -ne [datetime]::MinValue) {
        $Item.fileSystemInfo = @{ lastModifiedDateTime = $Modified.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture) }
    }

    $Window = [System.IO.MemoryStream]::new()
    $Plain = [System.IO.MemoryStream]::new()
    $Fragment = [byte[]]::new($FragmentSize)
    $Filled = 0
    $Decryptor = @{}
    $Format = $null
    $Position = [int64]0
    $Total = [int64]0
    $Sent = [int64]0
    $UploadUrl = $null
    $Uploaded = $null
    try {
        do {
            $Window.SetLength(0)
            $Received = Receive-CIPPCloudBackupObjectStream -Destination $Context.Destination -Key $StoredKey -VersionId ([string]$Entry.VersionId) -Offset $Position -Length $WindowSize -OutStream $Window
            if (-not $Received) {
                throw [System.Management.Automation.ItemNotFoundException]::new('This version of the file is no longer in the backup storage.')
            }
            $Stored = [int64]$Received.Bytes
            $Count = [int]$Window.Length
            $Buffer = $Window.GetBuffer()
            $Position += $Count
            $Final = $Position -ge $Stored
            if (-not $Final -and $Count -eq 0) { throw 'The backup storage returned no data for this file.' }

            if ($null -eq $Format) {
                $Magic = if ($Count -ge 8) { [System.Text.Encoding]::ASCII.GetString($Buffer, 0, 8) } else { '' }
                if ($Magic -eq 'CIPPENC2') {
                    if ($Count -lt 100) { throw 'The backed-up file is damaged: its encryption header is incomplete.' }
                    $Format = 'Encrypted'
                    $ChunkSize = ([int64]$Buffer[24] -shl 24) -bor ([int64]$Buffer[25] -shl 16) -bor ([int64]$Buffer[26] -shl 8) -bor [int64]$Buffer[27]
                    $Frames = [Math]::Floor(($Stored - 116) / ($ChunkSize + 16)) + 1
                    $Total = $Stored - 100 - 16 * [int64]$Frames
                    if ($ChunkSize -lt 1 -or $Stored -lt 116 -or $Total -lt 0) { throw 'The backed-up file is damaged: its size does not match its encryption format.' }
                } elseif ($Magic -eq 'CIPPENC1') {
                    if (-not $Final) { throw 'The backed-up file is in a format that file restore cannot stream.' }
                    $Format = 'Small'
                    $Whole = [byte[]]::new($Count)
                    [System.Array]::Copy($Buffer, 0, $Whole, 0, $Count)
                    $Decrypted = Unprotect-CIPPCloudBackupData -Bytes $Whole
                    $Total = $Decrypted.Length
                } else {
                    $Format = 'Plain'
                    $Total = $Stored
                }

                if ($Total -eq 0) {
                    $Uploaded = New-GraphPOSTRequest -uri "$ItemUri/content?@microsoft.graph.conflictBehavior=$ConflictBehavior" -tenantid $Tenant -AsApp $true -type 'PUT' -body '' -contentType 'application/octet-stream'
                    break
                }
                $Session = New-GraphPOSTRequest -uri "$ItemUri/createUploadSession" -tenantid $Tenant -AsApp $true -body (ConvertTo-Json -InputObject @{ item = $Item } -Depth 5 -Compress)
                $UploadUrl = [string]$Session.uploadUrl
                if (-not $UploadUrl) { throw 'Graph returned no upload URL.' }
            }

            if ($Format -eq 'Encrypted') {
                $Plain.SetLength(0)
                $null = Unprotect-CIPPCloudBackupStreamBlock -Decryptor $Decryptor -Buffer $Buffer -Count $Count -OutputStream $Plain -Final:$Final
                $Source = $Plain.GetBuffer()
                $SourceLength = [int]$Plain.Length
            } elseif ($Format -eq 'Small') {
                $Source = $Decrypted
                $SourceLength = $Decrypted.Length
            } else {
                $Source = $Buffer
                $SourceLength = $Count
            }

            $Index = 0
            while ($true) {
                $Take = [Math]::Min($FragmentSize - $Filled, $SourceLength - $Index)
                if ($Take -gt 0) {
                    [System.Array]::Copy($Source, $Index, $Fragment, $Filled, $Take)
                    $Filled += $Take
                    $Index += $Take
                }
                if ($Sent + $Filled -gt $Total) { throw 'The backed-up file is larger than its stored size says.' }
                if ($Filled -lt $FragmentSize -and -not ($Filled -gt 0 -and $Sent + $Filled -eq $Total)) { break }

                $Attempt = 0
                while ($true) {
                    $Attempt++
                    $Content = [System.Net.Http.ByteArrayContent]::new($Fragment, 0, $Filled)
                    $Content.Headers.ContentRange = [System.Net.Http.Headers.ContentRangeHeaderValue]::new($Sent, $Sent + $Filled - 1, $Total)
                    $Request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Put, $UploadUrl)
                    $Request.Content = $Content
                    $Response = $null
                    try {
                        # The pre-authenticated upload URL must not receive CIPP's bearer token.
                        $Response = $Client.SendAsync($Request).GetAwaiter().GetResult()
                        $Status = [int]$Response.StatusCode
                        if ($Status -lt 300) {
                            if ($Status -ne 202) {
                                $Uploaded = ConvertFrom-Json -InputObject $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                            }
                            break
                        }
                        $ErrorText = $Response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                        if ($Status -eq 409) {
                            $Conflict = [System.InvalidOperationException]::new("A file named '$Name' already exists in the target folder.")
                            $Conflict.Data['Conflict'] = $true
                            throw $Conflict
                        }
                        if (($Status -ne 429 -and $Status -lt 500) -or $Attempt -ge 4) {
                            throw "The upload was refused with status $($Status): $ErrorText"
                        }
                        $Wait = $Response.Headers.RetryAfter.Delta.TotalSeconds ?? [Math]::Pow(2, $Attempt)
                    } catch [System.Net.Http.HttpRequestException] {
                        if ($Attempt -ge 4) { throw "The upload failed: $($_.Exception.Message)" }
                        $Wait = [Math]::Pow(2, $Attempt)
                    } finally {
                        if ($Response) { $Response.Dispose() }
                        $Request.Dispose()
                    }
                    Start-Sleep -Seconds ([Math]::Min([double]$Wait, 60))
                }
                $Sent += $Filled
                $Filled = 0
            }
        } while (-not $Final)

        if ($Total -gt 0 -and ($Sent -ne $Total -or -not $Uploaded)) {
            throw "The upload ended after $Sent of $Total bytes."
        }
        $UploadUrl = $null
    } finally {
        if ($UploadUrl) {
            try { $null = $Client.DeleteAsync($UploadUrl).GetAwaiter().GetResult() } catch { $null = $_ }
        }
        if ($Decryptor.DataKey) { [System.Array]::Clear($Decryptor.DataKey, 0, $Decryptor.DataKey.Length) }
        $Window.Dispose()
        $Plain.Dispose()
    }

    [pscustomobject]@{
        Id    = [string]$Uploaded.id
        Name  = [string]($Uploaded.name ?? $Name)
        Bytes = $Total
    }
}

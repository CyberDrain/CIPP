function Write-CIPPCloudBackupItem {
    <#
    .SYNOPSIS
        Stores one backed-up item under the owner's prefix of a cloud backup run, encrypting it when the policy has a key.
    .DESCRIPTION
        Returns { Key; Bytes; VersionId; Size }: Bytes as stored, Size of the original content. The only way cloud backup workloads write content.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(DefaultParameterSetName = 'Body')]
    param(
        [Parameter(Mandatory = $true)]
        $Context,

        [Parameter(Mandatory = $true)]
        [string]$ItemKey,

        [Parameter(Mandatory = $true, ParameterSetName = 'Body')]
        [AllowEmptyCollection()]
        [byte[]]$Body,

        [Parameter(Mandatory = $true, ParameterSetName = 'Stream')]
        [System.IO.Stream]$Stream,

        [string]$ContentType = 'application/octet-stream',

        [hashtable]$Metadata
    )

    $Source = if ($PSCmdlet.ParameterSetName -eq 'Body') { [System.IO.MemoryStream]::new($Body, $false) } else { $Stream }
    try {
        $Params = @{
            Destination = $Context.Destination
            Key         = "$($Context.OwnerPrefix)$($ItemKey.TrimStart('/'))"
            Stream      = $Source
            ContentType = $ContentType
        }
        if ($Metadata) { $Params.Metadata = $Metadata }
        if ($Context.Key) {
            $Params.KeyId = $Context.KeyId
            $Params.EncryptionKey = $Context.Key
        }
        Send-CIPPCloudBackupObjectStream @Params
    } finally {
        if ($PSCmdlet.ParameterSetName -eq 'Body') { $Source.Dispose() }
    }
}

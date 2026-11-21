function Get-CIPPCloudBackupPermissionRole {
    <#
    .SYNOPSIS
        The Microsoft Graph application permissions cloud backup grants CIPP's app, as { Id; Name; Workloads }.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    # App role ids from https://learn.microsoft.com/en-us/graph/permissions-reference
    @(
        [pscustomobject]@{ Id = 'e2a3a72e-5f79-4c64-b1b1-878b674786c9'; Name = 'Mail.ReadWrite'; Workloads = @('exchange') }
        [pscustomobject]@{ Id = '99280d24-a782-4793-93cc-0888549957f6'; Name = 'MailboxFolder.Read.All'; Workloads = @('exchange') }
        [pscustomobject]@{ Id = 'fef87b92-8391-4589-9da7-eb93dab7dc8a'; Name = 'MailboxFolder.ReadWrite.All'; Workloads = @('exchange') }
        [pscustomobject]@{ Id = '7d9f353d-a7bd-4fbb-822a-26d5dd39a3ce'; Name = 'MailboxItem.Read.All'; Workloads = @('exchange') }
        [pscustomobject]@{ Id = '76577085-e73d-4f1d-b26a-85fb33892327'; Name = 'MailboxItem.ImportExport.All'; Workloads = @('exchange') }
        [pscustomobject]@{ Id = '798ee544-9d2d-430c-a058-570e29e34338'; Name = 'Calendars.Read'; Workloads = @('exchange') }
        [pscustomobject]@{ Id = '089fe4d0-434a-44c5-8827-41ba8a0b17f5'; Name = 'Contacts.Read'; Workloads = @('exchange') }
        [pscustomobject]@{ Id = '75359482-378d-4052-8f01-80520e7db3cd'; Name = 'Files.ReadWrite.All'; Workloads = @('onedrive', 'sharepoint') }
        [pscustomobject]@{ Id = '9492366f-7969-46a4-8d15-ed1a20078fff'; Name = 'Sites.ReadWrite.All'; Workloads = @('onedrive', 'sharepoint') }
        [pscustomobject]@{ Id = '6b7d71aa-70aa-4810-a8d9-5d9fb2830017'; Name = 'Chat.Read.All'; Workloads = @('teams') }
        [pscustomobject]@{ Id = '7b2449af-6ccd-4f4d-9f78-e550c193f0d1'; Name = 'ChannelMessage.Read.All'; Workloads = @('teams') }
        [pscustomobject]@{ Id = '2280dda6-0bfd-44ee-a2f4-cb867cfc4c1e'; Name = 'Team.ReadBasic.All'; Workloads = @('teams') }
        [pscustomobject]@{ Id = '59a6b24b-4225-4393-8165-ebaec5f55d7a'; Name = 'Channel.ReadBasic.All'; Workloads = @('teams') }
    )
}

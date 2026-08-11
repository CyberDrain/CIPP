# Mailbox Restores

Mailbox Restores lists the restore requests in the selected tenant and lets you create new ones. A restore copies the contents of a soft-deleted mailbox into a mailbox that still exists, which is how you recover the mail of a departed user whose license has been removed, or repopulate a mailbox that was deleted in error.

{% hint style="info" %}
A restore copies content into an existing target mailbox, it does not bring the deleted mailbox back. The source mailbox must still be within Exchange Online's retention window for soft-deleted mailboxes, otherwise it will not appear in the source list.
{% endhint %}

## Action Buttons

<details>

<summary>New Restore Job</summary>

Opens the **New Mailbox Restore** drawer. **Source Mailbox** lists the tenant's soft-deleted mailboxes and **Restore Target** lists its live mailboxes. Selecting either shows chips summarizing the mailbox type and whether it has an active archive, and the target also shows its current size, so you can judge whether it has room for the incoming content. **Restore Request Name** is filled in automatically once both mailboxes are chosen, and can be overwritten.

Everything under **Optional Settings** may be left alone for a straightforward restore.

| Field                           | Description                                                                                                                                                                                             |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Source Mailbox                  | The soft-deleted mailbox to copy content from. Required.                                                                                                                                                |
| Restore Target                  | The existing mailbox to copy content into. Required.                                                                                                                                                    |
| Restore Request Name            | The name the request is created under, which is how you will identify it in the table afterwards. Required, and prefilled with the source, the target and a unique identifier.                          |
| Bad Item Limit                  | How many corrupted items may be skipped before the restore fails. Left unset, Exchange Online applies its own default.                                                                                  |
| Large Item Limit                | How many items too large for the target may be skipped before the restore fails.                                                                                                                        |
| Completed Request Age Limit     | How long the completed request is kept before Exchange Online clears it away.                                                                                                                           |
| Associated Messages Copy Option | How hidden items associated with folders, such as views and rules, are handled. Choose Do Not Copy, Map By Message Class, or Copy.                                                                      |
| Exclude Folders                 | Folders to leave out of the restore. Pick from the well-known folders or type a folder path of your own.                                                                                                |
| Include Folders                 | Restricts the restore to these folders only. Pick from the well-known folders or type a folder path of your own.                                                                                        |
| Batch Name                      | A label for grouping several restores together, useful when recovering a set of mailboxes at once.                                                                                                      |
| Conflict Resolution Option      | What happens when an item already exists in the target. Choose Force Copy, Keep All, Keep Latest Item, Keep Source Item, Keep Target Item, or Update From Source.                                       |
| Source Root Folder              | Restores only this folder and everything beneath it, rather than the whole mailbox.                                                                                                                     |
| Target Root Folder              | Places the restored content under this folder in the target, rather than merging it into the existing folder structure. Setting this makes the restored mail easy to identify and easy to remove later. |
| Target Type                     | Whether the content lands in the target's Primary mailbox, its Archive, or a specific Mailbox Location.                                                                                                 |
| Exclude Dumpster                | Leaves the recoverable items (dumpster) content out of the restore.                                                                                                                                     |
| Source Is Archive               | Restores from the source mailbox's archive rather than its primary. Unavailable unless the source has an active archive.                                                                                |
| Target Is Archive               | Restores into the target's archive rather than its primary. Unavailable unless the target has an active archive.                                                                                        |

**Create Restore Job** submits the request and stays unavailable until a source, a target and a name are all present. **Cancel** discards the form.

{% hint style="warning" %}
Restoring into the target's primary mailbox without setting **Target Root Folder** merges the source content into the target's existing folders, which is difficult to unpick afterwards. Where you are recovering a leaver's mail into a colleague's mailbox, set a target root folder so the restored content stays separate.
{% endhint %}

</details>

## Table Details

| Column         | Description                                                                                   |
| -------------- | --------------------------------------------------------------------------------------------- |
| Name           | The name the restore request was created under.                                               |
| Status         | The current state of the request, such as Queued, InProgress, Suspended, Completed or Failed. |
| Target Mailbox | The mailbox the content is being copied into.                                                 |
| When Created   | When the request was created.                                                                 |
| When Changed   | When the request was last updated.                                                            |

The properties returned are for the Exchange Online PowerShell command `Get-MailboxRestoreRequest`. For more information on the command please see the [Microsoft documentation](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-mailboxrestorerequest?view=exchange-ps).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Resume Restore Request</td><td>Restarts a suspended request from where it left off.</td><td>true</td></tr><tr><td>Suspend Restore Request</td><td>Pauses a request that is queued or in progress, leaving the work already done in place.</td><td>true</td></tr><tr><td>Remove Restore Request</td><td>Deletes the request. Content already copied into the target mailbox is not removed.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

## Mailbox Restore Statistics

The flyout shows the full statistics for the selected request, which is where to look when a restore is slower than expected or has failed. Alongside the timestamps and durations it reports the items transferred, the bytes moved and the transfer rate, the counts of bad, large and missing items encountered, the data consistency score, and the percentage complete.

The properties returned are for the Exchange Online PowerShell command `Get-MailboxRestoreRequestStatistics`. For more information on the command please see the [Microsoft documentation](https://learn.microsoft.com/en-us/powershell/module/exchangepowershell/get-mailboxrestorerequeststatistics?view=exchange-ps).

**View Report** opens the detailed request report, a verbose log of everything Exchange Online did while processing the request. This is the most useful artefact to attach to a support case for a failed restore.

{% include "../../../../.gitbook/includes/feature-request.md" %}

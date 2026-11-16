# ActiveSync Devices

This report lists every mobile device partnership registered against a mailbox in the selected tenant, or across all tenants, one row per device. It shows what each device is, when it last synchronised, and whether Exchange Online currently allows or blocks it, so you can find stale partnerships and quarantined devices without opening Exchange Online PowerShell.

## Table Details

The properties returned are for the Exchange Online PowerShell command `Get-MobileDevice`. For more information on the command please see the [Microsoft documentation](https://learn.microsoft.com/powershell/module/exchangepowershell/get-mobiledevice).

**Device Access State** is the column the row actions work from, and is normally `Allowed`, `Blocked`, or `Quarantined`. **Device Access State Reason** says why: `Global` is the tenant's default access level (the usual cause of quarantine), `Individual` is the mailbox's own allow or block list, and `DeviceRule` or `Policy` is a device access rule or mobile device policy. **Mailbox Access List** shows whether the device is on that mailbox's allow list or block list, which is where **Allow Device** and **Block Device** add it. Use the **Quarantined** and **Blocked** filters to find devices that cannot sync.

A single tenant is read live from Exchange Online by default; switch the data source to cached to read the CIPP reporting database instead. All Tenants always reads the cached data, so sync it first if the table is empty.

CIPP also adds a column of its own, **Sync Info Note**: where the row is Outlook for iOS or Android, it explains that those apps use modern authentication and do not report ActiveSync sync times, which is why their sync columns can look empty or out of date.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Allow Device</td><td>Allows the device to synchronise with the mailbox. Greyed out where <strong>Device Access State</strong> is already <code>Allowed</code>.</td><td>true</td></tr><tr><td>Block Device</td><td>Stops the device synchronising with the mailbox. Greyed out where <strong>Device Access State</strong> is already <code>Blocked</code>.</td><td>true</td></tr><tr><td>Delete Device</td><td>Removes the device partnership from the mailbox entirely. This cannot be undone.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

Each action confirms first, naming the device and the mailbox it belongs to. Allowing and blocking are settings on the mailbox rather than on the device, so a device that synchronises several mailboxes needs the action running against each of its rows.

{% include "../../../../.gitbook/includes/feature-request.md" %}

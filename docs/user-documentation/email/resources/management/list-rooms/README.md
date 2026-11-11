# Rooms

This page lists the room mailboxes in the selected tenant. Each row brings the mailbox together with the room's location and facility details, so the address, capacity, and building sit alongside the mailbox name. Rooms are grouped for users with [README.md](../room-lists/ "mention").

## Action Buttons

<details>

<summary>Add Room Mailbox</summary>

Creates a new room mailbox in the selected tenant.

| Field                        | Description                                                                              |
| ---------------------------- | ---------------------------------------------------------------------------------------- |
| Display Name                 | The name shown in the address list and in booking dialogs. Required.                     |
| Username                     | The part before the @ symbol. Required.                                                  |
| Primary Domain name          | The domain used after the @ symbol, chosen from the tenant's verified domains. Required. |
| Resource Capacity (Optional) | The number of people the room seats. Left unset when the box is empty.                   |

**Create Room Mailbox** submits the form. Sign-in for the new mailbox is blocked as part of creating it, so nobody can sign in as the room. Once a mailbox has been created the button changes to **Create Another**, so the drawer can be reused without closing it. Everything else about the room, including its location, facilities, and booking behaviour, is set afterwards on the [edit.md](edit.md "mention") page.

</details>

<details>

<summary>Bulk Add Rooms</summary>

Creates several room mailboxes at once in the selected tenant, from a CSV file or from rows entered by hand.

**Download Example CSV** gives a file with the header row and two sample rooms showing what each column expects, one with a capacity and one without. The columns are the same fields as Add Room Mailbox: `displayName`, `username` and `domain` are required, and `resourceCapacity` is an optional whole number that is left unset when the cell is empty. Replace the sample rows with your own before uploading, or delete them from the preview. **Add Room Manually** opens a dialog with the same fields, with the domain chosen from the tenant's verified domains, for adding one row at a time.

Every row appears in the **Room Preview** table, where it can be checked and removed before submitting. Rows missing a display name, username or domain, or with a capacity that is not a whole number, are flagged above the table and block **Create Rooms** until they are fixed or removed. **Create Rooms** sends the rows one at a time, blocking sign-in for each new mailbox as Add Room Mailbox does, and the results panel reports each room separately. A row whose address already exists, or whose domain is not verified in the tenant, is rejected by Exchange and shown as an error, and the other rows still go through.

</details>

## Table Details

Each row combines the room's mailbox with its location and facility details, so the columns below are not a straight return from a single Exchange command.

| Column                            | Description                                                                                                                                                           |
| --------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name                      | The name of the room as it appears in the address list and in booking dialogs.                                                                                        |
| Mail                              | The address booking requests are sent to.                                                                                                                             |
| Building                          | The building the room is in.                                                                                                                                          |
| Floor                             | The floor the room is on.                                                                                                                                             |
| Capacity                          | The number of people the room seats, taken from the room's location details and falling back to the capacity set on the mailbox. Shows `0` when neither has been set. |
| City                              | The city the room is in.                                                                                                                                              |
| State                             | The state or province the room is in.                                                                                                                                 |
| Country Or Region                 | The country or region the room is in.                                                                                                                                 |
| Hidden From Address Lists Enabled | `true` when the room is hidden from the global address list, so it does not appear in the room finder.                                                                |

{% hint style="danger" %}
**Please note:** Because newly created, updated, and converted rooms will not be shown via Graph immediately and can take up to 24 hours to be visible a decision was made to switch to the slower method of polling Exchange PowerShell.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Room</td><td>Opens the <a data-mention href="edit.md">edit.md</a> page with the selected row's room pre-populated.</td><td>false</td></tr><tr><td>Edit permissions</td><td>Opens the <a data-mention href="../../../../identity/administration/users/user/exchange.md">exchange.md</a> page for the account behind the mailbox, where mailbox and calendar permissions are managed.</td><td>false</td></tr><tr><td>Block Sign In</td><td>Blocks sign-in for the selected room mailbox, so nobody can sign in as the room. Greyed out when sign-in is already blocked.</td><td>true</td></tr><tr><td>Unblock Sign In</td><td>Restores sign-in for the selected room mailbox. Greyed out unless sign-in is currently blocked.</td><td>true</td></tr><tr><td>Delete Room</td><td>Deletes the account behind the selected room mailbox, which removes the mailbox with it. Asks for confirmation first.</td><td>true</td></tr></tbody></table>

{% include "../../../../../../.gitbook/includes/feature-request.md" %}

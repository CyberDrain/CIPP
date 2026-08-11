# Equipment

This page lists the equipment mailboxes in the selected tenant. Equipment mailboxes are bookable resources that are not tied to a location, such as projectors, vehicles, and loan laptops. Each one is a mailbox with an account behind it, so the actions here cover both the mailbox and the account.

## Action Buttons

<details>

<summary>Add Equipment Mailbox</summary>

Creates a new equipment mailbox in the selected tenant.

| Field               | Description                                                                              |
| ------------------- | ---------------------------------------------------------------------------------------- |
| Display Name        | The name shown in the address list and in booking dialogs. Required.                     |
| Username            | The part before the @ symbol. Required.                                                  |
| Primary Domain name | The domain used after the @ symbol, chosen from the tenant's verified domains. Required. |

**Create Equipment Mailbox** submits the form. Sign-in for the new mailbox is blocked as part of creating it, so nobody can sign in as the resource. Once a mailbox has been created the button changes to **Create Another**, so the drawer can be reused without closing it.

</details>

## Table Details

The properties returned are for the Exchange Online PowerShell command `Get-Mailbox` with a filter for `EquipmentMailbox`. For more information on the command please see the [Microsoft documentation](https://learn.microsoft.com/en-us/powershell/module/exchange/get-mailbox?view=exchange-ps).&#x20;

{% hint style="danger" %}
**Please note:** Because newly created, updated, and converted equipment will not be shown via Graph immediately and can take up to 24 hours to be visible a decision was made to switch to the slower method of polling Exchange PowerShell.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Equipment</td><td>Opens the <a data-mention href="edit.md">edit.md</a> page for the selected row, where the name, address list visibility, contact and location details, booking behavior, and working hours can be changed.</td><td>false</td></tr><tr><td>Edit permissions</td><td>Opens the <a data-mention href="../../../../identity/administration/users/user/exchange.md">exchange.md</a> page for the account behind the mailbox, where mailbox and calendar permissions are managed.</td><td>false</td></tr><tr><td>Block Sign In</td><td>Blocks sign-in for the selected equipment mailbox, so nobody can sign in as the resource. New equipment mailboxes are already blocked when they are created.</td><td>true</td></tr><tr><td>Unblock Sign In</td><td>Restores sign-in for the selected equipment mailbox.</td><td>true</td></tr><tr><td>Delete Equipment</td><td>Deletes the account behind the selected equipment mailbox, which removes the mailbox with it. Asks for confirmation first.</td><td>true</td></tr></tbody></table>

{% include "../../../../../../.gitbook/includes/feature-request.md" %}

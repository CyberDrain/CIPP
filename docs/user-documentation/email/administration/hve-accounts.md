# HVE Accounts

High Volume Email (HVE) accounts are purpose-built Exchange Online accounts for sending bulk internal mail from apps and devices, such as invoices, alerts, and LOB notifications, without consuming a user license or hitting standard mailbox throttling limits. Use this page to create an HVE account in the selected tenant and grab the SMTP settings needed to wire it into your application.

## Action Buttons

<details>

<summary>Add HVE User</summary>

Creates an HVE account in the selected tenant. The drawer also shows the SMTP settings the sending application needs: server `smtp.hve.mx.microsoft` (the older `smtp-hve.office365.com` is deprecated), port `587`, STARTTLS with TLS 1.2 or 1.3, authenticating with the account's own credentials or an OAuth token.

| Field                | Description                                                                                   |
| -------------------- | --------------------------------------------------------------------------------------------- |
| Display Name         | The name the account is listed under. Required.                                               |
| Password             | The password the sending application authenticates with. Required, and at least 8 characters. |
| Primary SMTP Address | The full address the account sends as. Required, and validated as an email address.           |

**Create HVE User** submits the form. Once an account has been created the button changes to **Create Another User** and the form clears.

Creating an account also prepares the tenant for it. You are warned if Security Defaults are switched on, since HVE may not work while they are, and the new account is added to the exclusions of any Conditional Access policy that would otherwise block it from signing in. The results panel names each policy that was changed.

</details>

## Table Details

| Column                     | Description                                                                                             |
| -------------------------- | ------------------------------------------------------------------------------------------------------- |
| Display Name               | The name the HVE account is listed under.                                                               |
| Primary Smtp Address       | The address the account authenticates and sends as.                                                     |
| Alias                      | The mail nickname of the account.                                                                       |
| When Created               | When the account was created.                                                                           |
| Additional Email Addresses | Every secondary SMTP address on the account, comma separated. The primary address is not repeated here. |

The row flyout adds the account's billing policy, its Microsoft Entra object ID, and its alias and additional addresses in one place.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Display Name</td><td>Changes the display name of the selected HVE account.</td><td>false</td></tr><tr><td>Set Reply-To Address</td><td>Sets the address that replies to the account's mail are sent to.</td><td>false</td></tr><tr><td>Change Primary SMTP Address</td><td>Rebuilds the account's primary address from a username and a domain chosen from the tenant's verified domains. The tenant's default domain is offered first.</td><td>false</td></tr><tr><td>Assign Billing Policy</td><td>Assigns one of the tenant's HVE billing policies to the account. The confirmation shows the policy currently in force.</td><td>false</td></tr><tr><td>Remove Billing Policy</td><td>Takes the billing policy off the account. Greyed out on an account that does not have one.</td><td>false</td></tr><tr><td>Delete HVE Account</td><td>Deletes the selected HVE account(s). This cannot be undone.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

Every action other than **Delete HVE Account** works on a single account at a time and is not offered when several rows are selected.

{% include "../../../../.gitbook/includes/feature-request.md" %}

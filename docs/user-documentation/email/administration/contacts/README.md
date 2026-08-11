---
description: View & Edit Contacts in your M365 tenants
---

# Contacts

This page lists the Exchange Online mail contacts in the selected tenant. Mail contacts are external recipients that appear in the Global Address List but have no mailbox in the tenant, so they are the usual way of publishing a supplier, a helpdesk address, or a shared inbox belonging to another organization. Contacts can be created one at a time or pushed out in bulk from a saved template.

## Action Buttons

<details>

<summary>Add Contact</summary>

Opens a drawer that creates a mail contact in the currently selected tenant. Only the display name and email address are required, and everything else can be filled in later from [edit.md](edit.md "mention").

| Field                         | Description                                                                                                                                        |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name                  | The name the contact is listed under. Required.                                                                                                    |
| First Name                    | The contact's first name.                                                                                                                          |
| Last Name                     | The contact's last name.                                                                                                                           |
| Email                         | The external address mail to the contact is delivered to. Required, and validated as an email address.                                             |
| Hide from Global Address List | Keeps the contact out of the Global Address List so it can still be addressed directly but is not browsable.                                       |
| Job Title                     | The contact's job title.                                                                                                                           |
| Company Name                  | The company the contact belongs to.                                                                                                                |
| Mobile Phone                  | The contact's mobile number.                                                                                                                       |
| Business Phone                | The contact's business number.                                                                                                                     |
| Street Address                | The street part of the contact's address.                                                                                                          |
| City                          | The city for the contact.                                                                                                                          |
| State                         | The state or province for the contact.                                                                                                             |
| Postal Code                   | The postal code for the contact.                                                                                                                   |
| Website                       | A web address to record against the contact.                                                                                                       |
| Mail Tip                      | A short message Outlook shows to anyone composing mail to this contact, for example a note that the address is monitored only during office hours. |

**Create Contact** submits the form. Once a contact has been created the button changes to **Create Another** and the form clears, so several contacts can be added in one sitting.

</details>

<details>

<summary>Deploy Contact Template</summary>

Opens a drawer that creates mail contacts from one or more saved templates across one or more tenants. The same drawer is available from [README.md](../contacts-template/README.md "mention").

| Field             | Description                                                                                                                         |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Select Tenants    | The tenants the contacts are created in. More than one can be chosen, and the tenant you are currently on is preselected. Required. |
| Select a template | The templates to deploy. More than one can be chosen, and every selected template is created in every selected tenant. Required.    |

**Deploy Templates** submits the form. Once a deployment has run the button changes to **Deploy Another** and the selections clear, so a second batch can be sent without reopening the drawer.

If a mail contact with the same external email address already exists in a tenant, the template is skipped for that tenant and the results panel says so, so re-running a deployment does not create duplicates.

{% hint style="warning" %}
A contact that already exists is skipped, not updated. Changing a template and deploying it again does not correct contacts that were created from the earlier version.
{% endhint %}

</details>

## Table Details

The properties returned are for the Exchange Online PowerShell command `Get-Contact`. For more information on the command please see the [Microsoft documentation](https://learn.microsoft.com/powershell/module/exchangepowershell/get-contact).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Contact</td><td>Opens <a data-mention href="edit.md">edit.md</a> for the selected contact. Greyed out on a contact that is directory synced, which has to be changed at the source instead.</td><td>false</td></tr><tr><td>Set Source of Authority</td><td>Switches the contact between <code>Cloud Managed</code> and <code>On-Premises Managed</code>, so you can take over a synced contact in the cloud or hand it back to on-premises. The current setting is preselected, and handing a contact back does not show until the next directory sync cycle. Greyed out on a cloud-only contact, which has no on-premises counterpart to switch between.</td><td>true</td></tr><tr><td>Remove Contact</td><td>Deletes the mail contact from the tenant. Greyed out on a contact that is directory synced, which has to be removed at the source instead.</td><td>true</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}

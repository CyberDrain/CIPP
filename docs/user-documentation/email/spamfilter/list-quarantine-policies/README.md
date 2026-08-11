# Quarantine Policies

This page lists the quarantine policies in the selected tenant and shows the tenant's global quarantine notification settings above the table. A quarantine policy controls what end users are allowed to do with their own quarantined messages, and it is referenced from the tenant's anti-spam, anti-phishing, anti-malware, and Safe Attachments policies.

## Global Quarantine Settings

The card above the table shows the settings that govern the quarantine notification message itself. These apply to the whole organization rather than to any one policy. The refresh icon on the card reloads them without reloading the table.

| Item                   | Description                                                                                                                                                                                            |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Notification Frequency | How often end users are sent quarantine notifications, shown as 4 hours, Daily, or Weekly.                                                                                                             |
| Branding               | Whether the organization's branding is applied to those notifications.                                                                                                                                 |
| Custom Sender Address  | The address notifications are sent from, or `None` where the Microsoft default is used.                                                                                                                |
| Custom Language        | The languages configured for custom notification text. Select it to open the Custom Language Settings flyout, which lists the sender display name, subject, and disclaimer held against each language. |

Where the settings cannot be read for the selected tenant, every item shows `n/a`.

## Action Buttons

{% content-ref url="add.md" %}
[add.md](add.md)
{% endcontent-ref %}

<details>

<summary>Edit Settings</summary>

Opens the **Edit - Global Quarantine Settings** dialog, which changes the notification settings shown on the card. It acts on the selected tenant only.

| Field                            | Description                                                                                             |
| -------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Notification Frequency           | How often end users are sent quarantine notifications: **4 hours**, **Daily**, or **Weekly**. Required. |
| Custom Sender Address (Optional) | The address notifications are sent from. Leave it empty to use the Microsoft default.                   |
| Organization Branding            | Applies the organization's branding to the notification messages.                                       |

</details>

## Filters

Preset filters are available from the **Filters** button for **Custom Policies** and **Built-in Policies** rows.

## Table Details

| Column                                       | Description                                                                                  |
| -------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Name                                         | The name of the quarantine policy.                                                           |
| Release Action Preference                    | Whether end users can release a quarantined message themselves, or only request its release. |
| Delete                                       | Whether end users can delete quarantined messages.                                           |
| Preview                                      | Whether end users can preview quarantined messages.                                          |
| Block Sender                                 | Whether end users can add the sender to their blocked senders list.                          |
| Allow Sender                                 | Whether end users can add the sender to their allowed senders list.                          |
| Quarantine Notification                      | Whether end users receive quarantine notification messages for this policy.                  |
| Include Messages From Blocked Sender Address | Whether those notifications also cover messages from blocked senders.                        |
| When Created                                 | When the policy was created.                                                                 |
| When Changed                                 | When the policy was last modified.                                                           |

Microsoft supplies a set of built-in policies alongside any you create yourself. The built-in ones cannot be changed or removed, and the **Custom Policies** and **Built-in Policies** presets tell the two apart.

**More Info** opens a flyout with **Id**, **Name**, the full end-user permissions, **Guid**, **Builtin**, **When Created**, and **When Changed**.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Policy</td><td>Opens a form for the end-user permissions and notification settings on the policy. <strong>Policy Name</strong> is shown but cannot be changed. Greyed out on built-in policies.</td><td>true</td></tr><tr><td>Delete Policy</td><td>Deletes the policy from the tenant. It is removed even where it is still in use, so check first that it is not referenced by an anti-phishing, anti-spam, anti-malware, or Safe Attachments policy. Greyed out on built-in policies.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}

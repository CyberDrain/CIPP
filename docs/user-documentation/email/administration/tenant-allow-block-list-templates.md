# Tenant Allow/Block List Templates

Tenant allow/block list templates hold a saved set of entries for Exchange Online Protection's tenant allow/block list, so the same senders, URLs, file hashes, or IP addresses can be pushed out to many tenants instead of being typed into each one. Templates are not tied to a tenant. They are deployed through the **Tenant Allow/Block List Template** standard, which applies the entries to whichever tenants the standard is assigned to.

## Action Buttons

<details>

<summary>Add Template</summary>

Opens the **Save Tenant Allow/Block List Template** drawer.

| Field                | Description                                                                                                            |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Template Name        | The name the template is listed and selected under. Required.                                                          |
| Entries              | The values to allow or block, separated by commas or semicolons. Required, and validated against the chosen list type. |
| Notes                | Free text stored with the entries in Exchange, useful for recording why they were added.                               |
| List Type            | What the entries are: **Sender**, **Url/IPv4**, **FileHash**, or **IPv6**. Required.                                   |
| Block or Allow Entry | Whether the entries are blocked or allowed. Required.                                                                  |
| No Expiration        | Keeps the entries in place indefinitely rather than letting Exchange expire them.                                      |
| Remove After 45 Days | Removes the entries 45 days after they were last used.                                                                 |

**Save Template** stores the template. The drawer stays open afterwards with the button reading **Save Another**, so several templates can be created in one sitting.

The form adjusts itself as you choose a list type and method, since Exchange does not accept every combination:

| Rule                                                 | Behavior                                                                                                   |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| FileHash entries can only be blocked                 | Choosing **FileHash** forces the method to **Block** and locks the selector.                                |
| No Expiration is not available for every allow entry | It can be set on any block entry, and on allow entries only when the list type is **Url/IPv4** or **IPv6**. |
| Remove After 45 Days applies to allow entries only   | It can be set only on an allow entry whose list type is **Sender**, **Url/IPv4**, or **FileHash**.          |
| The two expiry switches are mutually exclusive       | Turning one on turns the other off.                                                                         |

Entry formats are validated before the template can be saved, and the hint under **Entries** changes to match the list type.

| List Type | Expected format                                                                                                                                                                                                                       |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sender    | Domains or email addresses, for example `contoso.com` or `user@example.com`. Wildcards are accepted in the form `*.domain.com`.                                                                                                       |
| Url/IPv4  | Hostnames, hostname paths such as `test.com/test`, IPv4 addresses, or IPv6 addresses. Do not include `http://` or `https://`. Entries are limited to 250 characters, and wildcards such as `*.domain.com` or `domain.*` are accepted. |
| FileHash  | SHA256 hashes, each exactly 64 characters.                                                                                                                                                                                            |
| IPv6      | IPv6 addresses only, in colon-hexadecimal or CIDR notation.                                                                                                                                                                           |

</details>

## Table Details

| Column                          | Description                                                       |
| ------------------------------- | ----------------------------------------------------------------- |
| Template Name                   | The name the template was saved under.                            |
| Entries                         | The values the template will add to the list.                     |
| List Type                       | The kind of entry: `Sender`, `Url`, `FileHash`, or `IP`.          |
| List Method                     | Whether the entries are added as `Block` or `Allow`.              |
| Notes                           | The note stored alongside the entries in Exchange.                |
| No Expiration                   | Whether the entries are set never to expire.                      |
| Remove After (Days of Last Use) | Whether the entries are set to be removed 45 days after last use. |

{% hint style="info" %}
**List Type** shows the value Exchange uses rather than the label on the form, so a template saved as **Url/IPv4** lists as `Url`, and one saved as **IPv6** lists as `IP`.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Template</td><td>Reopens the template in the drawer so its entries and settings can be changed. Saving overwrites the existing template rather than creating a new one, so tenants the template is already deployed to will pick up the change the next time the standard runs.</td><td>true</td></tr><tr><td>Delete Template</td><td>Permanently deletes the selected template(s).</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
Deleting a template does not remove anything from a tenant. Entries already deployed stay in the tenant's allow/block list and have to be removed from tenant-allow-block-lists. Any standard still pointing at the deleted template will log an error when it next runs.
{% endhint %}

## Deploying a Template

Templates do nothing on their own. To apply one, add the **Tenant Allow/Block List Template** standard to a standards template, select one or more of your saved templates in it, and assign it to tenants. See templates.

When the standard remediates, it reads the tenant's current allow/block list for that list type and submits only the entries that are not already there, so re-running it does not fail on duplicates. When it reports, it compares the template's entries against the tenant and flags any that are missing.

{% hint style="info" %}
The standard adds entries and never removes them. An entry deleted from a template is not withdrawn from the tenants it was already deployed to, and an entry added by hand in the tenant is left alone.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

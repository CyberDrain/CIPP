# Tenant Allow/Block Lists

Exchange Online Protection's tenant allow/block list holds the manual overrides that sit in front of the filtering stack: senders, URLs, file hashes, and IP addresses that a tenant should always block or always allow. This page shows every list type in a single table and lets you add entries to one tenant or several at once.

{% hint style="warning" %}
Allow entries weaken filtering and Microsoft treats them as temporary by design. Use them to unblock something Exchange has wrongly caught, not as a standing exemption, and prefer an expiring entry over one that never expires.
{% endhint %}

## Action Buttons

<details>

<summary>Add Entry</summary>

Opens the **Add Tenant Allow/Block List Entry** drawer.

| Field                | Description                                                                                                                      |
| -------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Select Tenants       | The tenants the entries are added to. More than one can be chosen, and the tenant you are currently on is preselected. Required. |
| Entries              | The values to allow or block, separated by commas or semicolons. Required, and validated against the chosen list type.           |
| Notes                | Free text stored with the entries in Exchange, useful for recording who asked for them and why.                                  |
| List Type            | What the entries are: **Sender**, **Url/IPv4**, **FileHash**, or **IPv6**. Required.                                             |
| Block or Allow Entry | Whether the entries are blocked or allowed. Required.                                                                            |
| No Expiration        | Keeps the entries in place indefinitely rather than letting Exchange expire them.                                                |
| Remove After 45 Days | Removes the entries 45 days after they were last used.                                                                           |

**Add Entry** submits the form. The drawer stays open afterwards with the button reading **Add Another**, so several entries can be added in one sitting.

The form adjusts itself as you choose a list type and method, since Exchange does not accept every combination:

| Rule                                                 | Behavior                                                                                                   |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| FileHash entries can only be blocked                 | Choosing **FileHash** forces the method to **Block** and locks the selector.                                |
| No Expiration is not available for every allow entry | It can be set on any block entry, and on allow entries only when the list type is **Url/IPv4** or **IPv6**. |
| Remove After 45 Days applies to allow entries only   | It can be set only on an allow entry whose list type is **Sender**, **Url/IPv4**, or **FileHash**.          |
| The two expiry switches are mutually exclusive       | Turning one on turns the other off.                                                                         |

Entry formats are validated before the form can be submitted, and the hint under **Entries** changes to match the list type.

| List Type | Expected format                                                                                                                                                                                                                       |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sender    | Domains or email addresses, for example `contoso.com` or `user@example.com`. Wildcards are accepted in the form `*.domain.com`.                                                                                                       |
| Url/IPv4  | Hostnames, hostname paths such as `test.com/test`, IPv4 addresses, or IPv6 addresses. Do not include `http://` or `https://`. Entries are limited to 250 characters, and wildcards such as `*.domain.com` or `domain.*` are accepted. |
| FileHash  | SHA256 hashes, each exactly 64 characters.                                                                                                                                                                                            |
| IPv6      | IPv6 addresses only, in colon-hexadecimal or CIDR notation.                                                                                                                                                                           |

{% hint style="info" %}
Each tenant is submitted separately, so a failure against one tenant does not stop the rest. The results panel reports the outcome for every tenant you selected, and it is worth reading rather than assuming a single success line covers them all.
{% endhint %}

</details>

## Table Details

| Column                          | Description                                                                                             |
| ------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Value                           | The sender, URL, file hash, or IP address the entry applies to.                                         |
| List Type                       | Which list the entry belongs to: `Sender`, `Url`, `FileHash`, or `IP`.                                  |
| Action                          | Whether the entry blocks or allows.                                                                     |
| Notes                           | The note recorded against the entry when it was created.                                                |
| Last Used Date                  | When Exchange last matched mail against the entry. Empty if it has never been used.                     |
| Last Modified Date Time         | When the entry was last changed.                                                                        |
| Expiration Date                 | When Exchange will remove the entry. Empty on an entry set never to expire.                             |
| Remove After (Days of Last Use) | The number of days after last use that the entry is removed, set to 45 when the removal option is used. |

{% hint style="info" %}
**List Type** shows the value Exchange uses rather than the label on the form, so an entry added as **Url/IPv4** lists as `Url`, and one added as **IPv6** lists as `IP`.
{% endhint %}

If a tenant does not support one of the four list types, that type is skipped and a warning is written to the CIPP logs. The other three still load, so a partial table is not necessarily an error.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Remove</td><td>Removes the entry from the tenant's allow/block list. Removal is immediate and the entry cannot be recovered, so a block that is still needed has to be added again.</td><td>true</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}

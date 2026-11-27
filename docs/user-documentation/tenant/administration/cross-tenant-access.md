# Cross-Tenant Access

Cross-tenant access decides how the tenant works with other Microsoft 365 organisations: whether people can be invited in either direction (B2B collaboration), whether Teams shared channels work across the two tenants (B2B direct connect), and whether the other organisation's MFA and device compliance count towards this tenant's Conditional Access (inbound trust).

This page shows the selected tenant's default settings, which apply to every organisation without its own settings, and each partner organisation that has its own. You can change the default settings, add partner organisations, change them and remove them.

With one tenant selected the page reads the tenant live; switch to cached data to see when it was last collected. With All Tenants selected it shows every tenant from the cache, so you can see across customers which partners are trusted and how. Use **Sync** to refresh the cache.

## Table Details

| Column | Description |
| --- | --- |
| Tenant | The tenant the row belongs to. Shown with All Tenants selected. |
| Organisation | **Default (all other organisations)** for the default settings, otherwise the partner organisation's name. |
| Partner Domain | The partner organisation's default domain. |
| Tenant ID | The partner organisation's tenant ID. |
| B2B Collaboration Inbound / Outbound | Whether the other organisation's users can be invited into this tenant (inbound), and whether this tenant's users can be invited into theirs (outbound). |
| B2B Direct Connect Inbound / Outbound | Whether users can join Teams shared channels across the two tenants without a guest account. |
| Trust MFA / Compliant Devices / Hybrid-Joined Devices | Whether MFA, a compliant device or a hybrid-joined device from the other organisation satisfies this tenant's Conditional Access. |
| Auto Redeem Inbound / Outbound | Whether invitations are redeemed automatically, without the consent prompt. Partner organisations only. |

A setting reads **Allowed** or **Blocked** when it covers all users and all applications, **Uses default** when a partner follows the default settings, and **Specific users or apps** when it was set up in Entra for particular users, groups or applications.

## Actions

| Action | Description |
| --- | --- |
| Add partner organisation | Adds an organisation by domain or tenant ID with its own settings. Settings left on **Use the default settings** follow the default. Not available with All Tenants selected. |
| Edit default settings | Changes the default settings. B2B collaboration and B2B direct connect can be allowed or blocked for everyone; **Leave unchanged** keeps a setting that targets specific users or apps. |
| Edit partner | Changes a partner organisation's settings, including whether it uses the default inbound trust or its own. |
| Remove partner | Removes the partner organisation's own settings, so the default settings apply to it again. |

{% hint style="info" %}
Microsoft takes up to a minute to show a change, so a partner you just added or removed may not appear in the list straight away.
{% endhint %}

{% hint style="info" %}
To set the same partner organisation on many tenants, for example to trust MFA from your own tenant everywhere, use the **Cross-Tenant Access Partner Organisation** standard in a baseline. Enter `%partnertenantid%` as the partner to use your own tenant.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

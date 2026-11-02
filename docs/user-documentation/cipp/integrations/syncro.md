---
description: Configuring the Syncro ticketing integration
---

# Syncro

The Syncro integration raises tickets in Syncro from CIPP alerts. Once it is configured and tenants are mapped to Syncro customers, any alert configured to deliver to a PSA is raised as a new ticket against the matching customer, with the priority you choose.

This is the first version of the integration. Every alert creates a new ticket. Adding repeat alerts to an existing ticket as a note, and linking tickets to the affected user, are not available yet.

## Creating an API Key in Syncro

{% stepper %}
{% step %}
#### Open the API token settings

In Syncro go to **Admin** > **API** > **API Tokens** and select **New Token**.
{% endstep %}

{% step %}
#### Choose the permissions

Give the token a name such as _CIPP Integration_ and grant it at least **Customers - List/Search** and **Tickets - Create**. Keep the token limited to the permissions it actually needs.
{% endstep %}

{% step %}
#### Store the key

Copy the generated key and store it securely. It is only shown once.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
Tickets raised by CIPP are created by the Syncro user the API key belongs to. A dedicated user makes CIPP's tickets easy to tell apart in Syncro.
{% endhint %}

## Configuring the Integration in CIPP

{% stepper %}
{% step %}
#### Enable the integration

Turn on **Enable Integration**. The remaining fields stay disabled until it is on.
{% endstep %}

{% step %}
#### Enter the subdomain

In **Syncro Subdomain**, enter the first part of your Syncro URL, for example `yourcompany` for `yourcompany.syncromsp.com`. Pasting the full URL also works.
{% endstep %}

{% step %}
#### Enter the API key

Paste the key captured earlier into **Syncro API Key**. Leaving it blank on a later save keeps the stored value.
{% endstep %}

{% step %}
#### Save and test

Select **Submit** to save, then select **Test**. A green banner confirms CIPP can authenticate and names the Syncro user the key belongs to. It also checks that the user can read customers and create tickets, and says so if either is missing.
{% endstep %}

{% step %}
#### Map your tenants

Move to the **Tenant Mapping** tab and map each CIPP tenant to its Syncro customer, then select **Submit**.
{% endstep %}
{% endstepper %}

## Settings

| Setting                 | Description                                                                                                                                                                                       |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enable Integration      | Turns the integration on. Every other setting, the **Test** and **Create Test Ticket** buttons, and the **Tenant Mapping** tab remain unavailable until this is enabled and saved.                 |
| Syncro Subdomain        | The subdomain of your Syncro instance. A full URL is reduced to the subdomain automatically.                                                                                                      |
| Syncro API Key          | The API key created in Syncro. Stored securely and masked once saved; leave blank on subsequent saves to keep the existing value.                                                                 |
| Syncro Default Priority | Optional. Sets the priority on every CIPP-generated ticket, unless an alert sets its own. One of Syncro's four priorities: 0 Urgent, 1 High, 2 Normal or 3 Low. Leave blank to use Syncro's default. |
| Syncro Problem Type     | Optional. The issue type stamped on every CIPP-generated ticket. Must match an existing issue type in Syncro exactly.                                                                              |
| Syncro Initial Status   | Optional. The status new tickets are created with. Must match an existing ticket status in Syncro exactly. Leave blank for New.                                                                   |

### Tenant Mapping

The **Tenant Mapping** tab pairs each CIPP tenant with a Syncro customer. An alert for an unmapped tenant is reported as a failure rather than raised against a customer CIPP had to guess, so mapping is required before the integration is useful.

{% hint style="warning" %}
Saving on the **Tenant Mapping** tab requires a role with unrestricted tenant access, meaning **Allowed Tenants** left as `AllTenants` with nothing in **Blocked Tenants**. A role scoped to particular tenants or tenant groups can read the existing mappings but is refused when it selects **Submit** or **Automap Companies**. See [roles.md](../../../setup/setting-up-cipp/roles.md "mention").
{% endhint %}

To add a mapping manually, choose a tenant and a Syncro customer, then select the add button, and select **Submit** to save. Selecting **Automap Companies** matches automatically, and the refresh button reloads the customer list from Syncro.

| Column          | Description                                              |
| --------------- | -------------------------------------------------------- |
| IntegrationName | The name of the Syncro customer the tenant is mapped to. |
| Tenant          | The display name of the mapped Microsoft 365 tenant.     |
| TenantDomain    | The default domain name of the mapped tenant.            |
| TenantId        | The tenant's Microsoft customer ID.                      |

Individual mappings can be removed with the **Delete Mapping** row action.

{% hint style="info" %}
Syncro customers carry no Microsoft tenant ID, so automapping matches on business name only: a tenant is mapped to the Syncro customer whose business name exactly matches the tenant's display name. Existing mappings are never overwritten, and these mappings are saved immediately, so there is no need to select **Submit** afterwards. A name shared by more than one Syncro customer is skipped and named in the result, and that tenant can be mapped manually.

**Automap Companies** also suggests looser name matches that ignore case, punctuation and legal suffixes such as Ltd or LLC. Those appear in the table but are only saved when you select **Submit**.

While the integration is enabled, CIPP also runs the exact name matching automatically every two hours, so newly added tenants are mapped without visiting this page.
{% endhint %}

## Testing the Integration

Two buttons at the top of the page verify different things.

| Button             | Description                                                                                                                                                        |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Test               | Authenticates against Syncro using the saved key and reports whether the connection succeeded and which permissions the key has. It does not create anything.        |
| Create Test Ticket | Raises a real ticket in Syncro using the configured problem type, status and default priority, confirming end-to-end delivery. It is safe to close the resulting ticket. |

{% hint style="warning" %}
The test ticket is raised against the first mapped Syncro customer. With no tenant mapped, the button reports that and creates nothing.
{% endhint %}

The test ticket is created directly rather than through the alert pipeline, so it does not exercise the `[CIPP]` title prefix.

## How Alert Tickets Are Raised

Ticket subjects are prefixed with `[CIPP]` so that CIPP-generated tickets are easy to identify and filter in Syncro. The alert body is attached as a hidden comment with customer email suppressed, so raising a ticket never emails the customer.

The priority on each ticket is the **PSA Ticket Priority** set on the alert where one is chosen, otherwise the integration's **Syncro Default Priority**, otherwise Syncro's own default. When HaloPSA is enabled as well, the per-alert priority list belongs to HaloPSA; Syncro tickets then use the Syncro default priority.

{% include "../../../../.gitbook/includes/feature-request.md" %}

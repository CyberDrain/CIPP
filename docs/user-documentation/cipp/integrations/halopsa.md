---
description: Configuring the Halo PSA Ticketing integration
---

# Halo PSA

The Halo PSA integration raises tickets in HaloPSA from CIPP alerts. Once it is configured and tenants are mapped to Halo clients, any alert configured to deliver to a PSA is raised as a ticket against the matching client.

## Creating an API Application in HaloPSA

{% stepper %}
{% step %}
#### Open the API configuration

In your Halo instance go to **Configuration** > **Integrations** > **Halo PSA API**, then select **View Applications**.
{% endstep %}

{% step %}
#### Create the application

Select **New**, give the application a name such as _CIPP Integration_, and make sure **Active** is ticked.
{% endstep %}

{% step %}
#### Set the authentication method

Set **Authentication Method** to _Client ID and Secret (Services)_, then store the **Client ID** and **Client Secret** securely. The secret is only shown once.
{% endstep %}

{% step %}
#### Choose the agent

Set the **Login Type** and **Agent to login as**. This determines who appears to be responsible for the tickets CIPP raises, so a dedicated agent is usually preferable.

The agent needs Tickets Access Level of Read and Modify, Clients Access Level of Read and Modify, and **Can add new Tickets** set to Yes. Administrator has been tested; other roles may work but have not been verified.
{% endstep %}

{% step %}
#### Grant permissions

On the **Permissions** tab, grant the application `read:tickets`, `edit:tickets`, `read:customers` and `edit:customers`. Keep the application limited to the permissions it actually needs.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
Two optional features need a little more than the baseline. Automapping reads Halo's own Microsoft 365 integration settings, so the API agent must be able to view them. Linking tickets to affected users reads contacts within each client.
{% endhint %}

## Configuring the Integration in CIPP

{% stepper %}
{% step %}
#### Enable the integration

Turn on **Enable Integration**. The remaining fields stay disabled until it is on.
{% endstep %}

{% step %}
#### Enter the URLs

Enter your Halo URL with `/api` appended in **HaloPSA Resource Server URL**, for example `https://yourcompany.halopsa.com/api`, and with `/auth` appended in **HaloPSA Authorization Endpoint URL**, for example `https://yourcompany.halopsa.com/auth`.
{% endstep %}

{% step %}
#### Enter the tenant

In **HaloPSA Tenant**, enter the first part of your Halo URL, for example `yourcompany`. Leave it blank if you are self-hosting.
{% endstep %}

{% step %}
#### Enter the credentials

Paste the **Client ID** and **Client Secret** captured earlier into **HaloPSA Client ID** and **HaloPSA Client Secret**. Leaving the secret blank on a later save keeps the stored value.
{% endstep %}

{% step %}
#### Save and test

Select **Submit** to save, then select **Test**. A green banner confirms CIPP can authenticate; a red banner means the credentials or URLs need correcting in Halo or CIPP.
{% endstep %}

{% step %}
#### Choose a ticket type

Select a **HaloPSA Ticket Type**. This drives the workflow used for CIPP tickets and populates the priority and outcome lists, so the remaining settings only appear once it is set. Save again after making changes.
{% endstep %}

{% step %}
#### Map your tenants

Move to the **Tenant Mapping** tab and map each CIPP tenant to its Halo client, then select **Submit**.
{% endstep %}
{% endstepper %}

## Settings

| Setting                            | Description                                                                                                                                                                                                                                                                                                  |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Enable Integration                 | Turns the integration on. Every other setting, the **Test** and **Create Test Ticket** buttons, and the **Tenant Mapping** tab remain unavailable until this is enabled and saved.                                                                                                                           |
| HaloPSA Resource Server URL        | The API endpoint for your Halo instance, ending in `/api`.                                                                                                                                                                                                                                                   |
| HaloPSA Authorization Endpoint URL | The authentication endpoint for your Halo instance, ending in `/auth`.                                                                                                                                                                                                                                       |
| HaloPSA Tenant                     | The tenant identifier for hosted Halo instances. Leave blank when self-hosting.                                                                                                                                                                                                                              |
| HaloPSA Client ID                  | The Client ID of the API application created in Halo.                                                                                                                                                                                                                                                        |
| HaloPSA Client Secret              | The Client Secret of the API application. Stored securely and masked once saved; leave blank on subsequent saves to keep the existing value.                                                                                                                                                                 |
| HaloPSA Ticket Type                | The ticket type used for CIPP alert tickets. Sets the workflow, and determines which priorities and outcomes are offered below. Leave blank to use Halo's default.                                                                                                                                           |
| HaloPSA Default Priority           | Optional. Sets the priority on every CIPP-generated ticket. Only priorities on the ticket type's SLA are listed. Leave blank to use the SLA default. Appears once a ticket type is selected.                                                                                                                 |
| Consolidate Tickets                | Adds repeat alerts with the same title to the existing open ticket as a private note rather than raising a new ticket. Appears once a ticket type is selected.                                                                                                                                               |
| HaloPSA Outcome                    | The action applied when a duplicate alert is added to an existing ticket. Only outcomes from the selected ticket type's workflow are listed, and the action must be one the Halo API user can run. Leave blank to use Halo's built-in Internal Note action. Appears once **Consolidate Tickets** is enabled. |
| Link Tickets to affected Users     | Raises one ticket per affected user and links it to the matching Halo contact. Appears once a ticket type is selected.                                                                                                                                                                                       |

{% hint style="info" %}
Some entries in the priority and outcome lists are guidance rows rather than real values, such as a prompt to select a ticket type first. They cannot be selected, and any previously saved value of this kind is cleared automatically.
{% endhint %}

### Tenant Mapping

The **Tenant Mapping** tab pairs each CIPP tenant with a Halo client. Alerts for an unmapped tenant have no client to be raised against, so mapping is required before the integration is useful.

To add a mapping manually, choose a tenant and a Halo client, then select the add button, and select **Submit** to save. Selecting **Automap Companies** matches automatically, and the refresh button reloads the client list from Halo.

| Column          | Description                                          |
| --------------- | ---------------------------------------------------- |
| IntegrationName | The name of the Halo client the tenant is mapped to. |
| Tenant          | The display name of the mapped Microsoft 365 tenant. |
| TenantDomain    | The default domain name of the mapped tenant.        |
| TenantId        | The tenant's Microsoft customer ID.                  |

Individual mappings can be removed with the **Delete Mapping** row action.

{% hint style="info" %}
Automapping for Halo PSA matches on the Microsoft tenant IDs that Halo stores against each client through its own Azure AD / Microsoft 365 integration, rather than guessing from company names. Existing mappings are never overwritten, and the mappings it creates are saved immediately, so there is no need to select **Submit** afterwards.

When it finishes, CIPP reports how many tenants were newly mapped and how many are now mapped in total. The same summary is written to the Logbook, along with a line for each mapping created, which is the place to look if a tenant you expected did not appear.
{% endhint %}

{% hint style="warning" %}
Two situations leave a tenant unmapped.

Where the same Microsoft tenant ID is recorded against more than one Halo client, CIPP cannot tell which is correct and skips that tenant. The competing clients are named in the Logbook, and the tenant can be mapped manually.

Where Halo's Microsoft 365 integration has not been set up, no tenant IDs are available at all and automapping reports that there is nothing to match against. Map the tenants manually in that case.
{% endhint %}

## Testing the Integration

Two buttons at the top of the page verify different things.

| Button             | Description                                                                                                                                                   |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Test               | Authenticates against Halo using the saved credentials and reports whether the connection succeeded. It does not create anything in Halo.                     |
| Create Test Ticket | Raises a real ticket in Halo using the configured ticket type and default priority, confirming end-to-end delivery. It is safe to close the resulting ticket. |

{% hint style="warning" %}
The test ticket is raised against the first mapped Halo client. If no usable mapping exists it falls back to client ID 1, which may not be a client you expect. Map your tenants before using this button.
{% endhint %}

The test ticket is created directly rather than through the alert pipeline, so it does not exercise the `[CIPP]` title prefix or per-user ticket linking.

## How Alert Tickets Are Raised

Ticket titles are prefixed with `[CIPP]` so that CIPP-generated tickets are easy to identify and filter in Halo.

When **Consolidate Tickets** is enabled, CIPP records the ticket it raised for each combination of client and alert title. A later alert with the same title is added to that ticket as a private note, using the configured outcome. If the ticket has since been closed, or the note cannot be added — most often because the Halo API user is not permitted to run the chosen outcome — a new ticket is created instead, so the alert is never lost.

When **Link Tickets to affected Users** is enabled, CIPP raises a separate ticket per affected user and matches them to a Halo contact within the mapped client, first on Microsoft Entra Object ID and then on email address or network login. Where no contact matches, the ticket is assigned to the client's General User and the affected user's UPN is included in the ticket body.

{% include "../../../../.gitbook/includes/feature-request.md" %}

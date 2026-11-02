# CIPP-API & MCP

{% hint style="warning" %}
Self-hosted clients who originally deployed CIPP prior to v7.1, please see [#pre-version-7.1-self-hosted-deployments](cipp-api.md#pre-version-7.1-self-hosted-deployments "mention") for how to set up and configure your API for use before proceeding with this page.

If you're using a **hosted CIPP instance**, you can follow the instructions below to set up and manage your API clients with no additional steps.
{% endhint %}

## **Creating an API Client (App Registration)**

1. Navigate to CIPP > Integrations and click on CIPP-API.
2. Creating an API client:
   1. If you need to create an API Client
      1. Click on Actions > Create New Client.
      2. Fill out the form with the App Name.
   2. If you've already created an App Registration and would like to import it:
      1. Click on Actions > Add Existing Client.
      2. Select the API Client from the list. The CIPP-SAM and CIPP-SSO applications are never offered here and cannot be added, reset or deleted as API clients; manage them from [credentials.md](../advanced/authentication/credentials.md "mention") instead.
   3. Ensure that you Enable the client in order to save it to the Function App authentication settings.
   4. Optionally set the [#custom-roles](../../../setup/setting-up-cipp/roles.md#custom-roles "mention") and Allowed IP Ranges for additional security.
   5. Select if you want MCP Access Allowed for this client. Enabling MCP Access sets this client up as an MCP connector app (the app your AI signs in as); CIPP automatically creates and manages a separate shared **CIPP-MCP** resource app that the tokens are issued for. You can enable MCP Access on more than one client. Connectors that sign a user in run with that user's own CIPP role; the client's role and IP range only apply when the client calls with its own secret and no user. MCP Access is only supported on the latest CIPP infrastructure. See [#enable-the-mcp-feature](cipp-api.md#enable-the-mcp-feature "mention") for more information.
   6. Submit the form to create the client. Remember to copy the Application secret to a secure location.
3. Once you have the API Client(s) configured, click Actions > Save to Azure, this updates the Function App authentication settings with the new Client IDs.

{% hint style="info" %}
The IP Range list supports both IPv4 and IPv6 addresses as standalone IP addresses or in CIDR Notation (for example 12.34.56.78/24 or 1.1.1.1).
{% endhint %}

{% hint style="info" %}
Custom Roles will limit which API endpoints each API Client can access. This can be used to limit all API calls to read only for example.
{% endhint %}

## API Usage

{% hint style="info" %}
The usage figures need the SuperAdmin role. On instances where egress accounting isn't enabled, such as most self-hosted deployments, the tab shows "API egress accounting is not enabled on this instance." instead.
{% endhint %}

The **API Usage** tab on the CIPP-API page holds the **API Egress** card, which shows how much data this instance has served and which endpoints served it. Use the **24h**, **3d** and **7d** toggle in the card header to set the trend window.

**Daily total**

A gauge shows today's API client egress against the instance's daily cap. It turns amber at 80% and red once the cap is reached, at which point further API client requests are turned away with a 429 response and the card shows how many were refused today. Where no cap is set, the card shows today's total on its own. Below the gauge, a separate line gives today's traffic from signed-in users, which is shown for information only and never counts towards the cap.

**Trend**

A stacked chart shows each API client's egress over the selected window. Hover over a point to see the endpoints that served the most data in that interval.

**Top endpoints today**

A table of today's endpoints, ordered by the data they served. Use **Endpoints for** to switch between **All API clients**, a single API client, and **Signed-in users (not capped)**. Graph requests are grouped by resource with IDs removed, so requests for different users' group memberships count as one endpoint, and MCP traffic is grouped by tool.

| Column      | Description                                                  |
| ----------- | ------------------------------------------------------------ |
| Endpoint    | The endpoint or MCP tool.                                    |
| Egress      | Data served by this endpoint today.                          |
| Requests    | Number of requests today.                                    |
| AvgSize     | Average response size.                                       |
| MaxSize     | Largest single response.                                     |
| Cache Hit % | Share of requests answered from cache.                       |
| Errors      | Requests that returned an error.                             |
| Shed        | Requests turned away because the daily cap had been reached. |

The API Client table on the **Settings** tab also has an **Egress Today** column with each client's own total for today. It shows `-` for a client with no recorded traffic, or where accounting isn't enabled.

## Using an API Client

After creating your first API client, the page will update to include additional information that is necessary for your automation:

- Token URL: This URL is what you will need when authenticating your automation to your CIPP instance. See [setup-and-authentication.md](../../../api-documentation/setup-and-authentication.md "mention") for more information.
- Tenant ID: This is the tenant ID for the tenant used to authenticate CIPP where your CIPP service account lives, this may take 5-15 minutes before it updates from when you create your first API client and press save.
- API URL: This will be the base URL required for all post-authenticated calls. Note that most automation tools will require you to append `/api` to this base URL for successful responses.

## **Disabling an API Client**

1. Navigate to CIPP > Integrations and click on CIPP-API.
2. Find the API client in the table and click on the 3 dots in the Actions column > Edit.
3. Flip the Enabled switch off and click Submit.
4. At the top of the page, go to Actions and click Save to Azure.

## **Rotating Secrets**

1. Navigate to CIPP > Integrations and click on CIPP-API.
2. Find the API client in the table and click on the 3 dots in the Actions column > Reset Application Secret.
3. Copy the new Secret to a secure location.

## **Troubleshooting**

- If you are getting permission errors when creating an API Client, check the CIPP-SAM application to ensure the permissions listed in the error are added and consented by an admin.
- If you have multiple CIPP-SAM apps, use the [#permissions-check](../settings/permissions.md#permissions-check "mention") to figure out which one you're using.

{% hint style="info" %}
**Want to Build Against the API?**

For full authentication examples, usage patterns, and endpoint information, see the [setup-and-authentication.md](../../../api-documentation/setup-and-authentication.md "mention") section within the API Documentation section.
{% endhint %}

## CIPP MCP

The CIPP MCP allows you to add CIPP to any AI you use and immediately talk to it in natural language. For example, you can ask "List all tenants with unassigned licences" or "list all users for tenant MySpecialTenant.com". To set up the MCP, follow these instructions:

{% hint style="warning" %}
**Self-hosted instances must be on the new infrastructure.** The MCP is only available on CIPP's new infrastructure. If you self-host CIPP on the legacy Function App infrastructure, you cannot use it until you migrate. For the steps, see [migrating-to-the-new-infrastructure.md](../../../setup/maintaining-cipp/migrating-to-the-new-infrastructure.md "mention").
{% endhint %}

{% hint style="warning" %}
**Connected the MCP before version 11?** Version 11 changed how the MCP signs in, so existing connections stop working and CIPP has to be added to your AI again. Select **Actions → Save to Azure** on the API Clients tab so CIPP creates the new **CIPP-MCP** resource app, then remove CIPP from your AI and add it back using the **Connector URL** shown for your client on the **MCP** tab of the CIPP-API integration.

If the MCP tab reports that setup is blocked, an app registration left over from the previous setup is still using the MCP address. Delete it in Entra, remove it from **API Clients** if it is listed there, and select **Save to Azure** again.
{% endhint %}

{% hint style="info" %}
**No client ID or secret needed.** CIPP publishes its OAuth details at a standard discovery address, so supported AI clients configure themselves from the MCP URL alone.
{% endhint %}

{% stepper %}
{% step %}

### Enable the MCP Feature

In CIPP: **CIPP → Application Settings → Features** → turn on **MCP Server**.
{% endstep %}

{% step %}

### Create the MCP API Client

Open the [cipp-api.md](cipp-api.md "mention") page and **Create New Client** (or edit an existing one). Set:

| Field                  | Value                                                                                            |
| ---------------------- | ------------------------------------------------------------------------------------------------ |
| **Role**               | `Readonly` (recommended), or a custom read role. Only applies when something calls with this client's own ID and secret and no user signs in (client credentials). Connectors that sign a user in run with that user's own CIPP role. |
| **IP range**           | `Any`. The connector calls in from your AI provider's servers, so you can't pin it to your office IPs. |
| **Enable this client** | On                                                                                               |
| **MCP Access Allowed** | **On**                                                                                           |

{% hint style="warning" %}
**Watch IP restrictions with MCP.** MCP requests arrive from your AI provider's cloud IPs (Anthropic, OpenAI, Microsoft), not your network, so an allowed-IP range blocks the connector with a 403. For connectors that sign a user in, that's the IP restriction on the **user's** CIPP role. For client-credentials calls, it's the client's own **IP range** and its **role**. Leave the client's IP range as `Any`, and make sure the roles your MCP users hold have no IP restriction. CIPP flags restricted MCP clients on the API Clients page and in the client dialog.
{% endhint %}

{% endstep %}

{% step %}

### Save to Azure

Click **Actions → Save to Azure**. This does all the Entra/Azure configuration for you automatically, including the callback URLs of the AI providers CIPP supports out of the box:

- **Claude** (`claude.ai` and `claude.com` for legacy purposes)
- **ChatGPT** connectors
- **Visual Studio Code** / GitHub Copilot Chat
- **Copilot Studio** and Microsoft 365 Copilot agents
- Local desktop and CLI clients, via a loopback callback

The instance restarts. Give it up to \~60 seconds before connecting. For AI providers CIPP doesn't list, and how the two-app model and Conditional Access work, see the collapsible sections after these steps.

{% endstep %}

{% step %}

### Add the Connector in Your LLM

Add CIPP as a custom connector in your AI and give it the MCP URL. That's all you need: no client ID and no secret. The URL is `https://<your-cipp-api-url>/api/ExecMCP` and can be found on the API page.

Click **Connect**. You'll be redirected to your normal Microsoft / CIPP sign-in, so log in and approve. Your LLM completes the connection and CIPP's read tools appear. The connector acts as you: every call runs with your own CIPP role, so each person who connects needs a CIPP role that covers the tools they use.

If you have **more than one** MCP client enabled, add `?client=<client-id>` to the URL (for example `https://<your-cipp-api-url>/api/ExecMCP?client=<client-id>`) so the connector signs in as that specific client. With a single MCP client the bare URL is fine. CIPP shows the exact per-client URL on the **MCP** tab of the CIPP-API integration.

{% hint style="info" %}
**Copilot Studio / Microsoft 365 Copilot agents are the exception.** They sign in as a confidential client with a secret, so follow [#copilot-studio-and-microsoft-365-copilot-agents](cipp-api.md#copilot-studio-and-microsoft-365-copilot-agents "mention") instead of this step. If your connection drops or the AI asks for a client ID, see the troubleshooting section below.
{% endhint %}
{% endstep %}

{% step %}

### Verify

Ask your AI something like:

> _Using CIPP, list all my tenants._

If tools show up and return data, you're done.
{% endstep %}
{% endstepper %}

<details>

<summary>How MCP authentication works (two apps and Conditional Access)</summary>

**Two apps.** The API client you flag _MCP Access Allowed_ is the app the AI signs in as (the OAuth client); it carries the redirect URIs. CIPP also creates and manages a single shared resource app, **CIPP-MCP**, which is the protected resource the token is issued for. Keeping the client and the resource separate is what lets your AI silently refresh its token in the background; if one app were both, Entra rejects the refresh (`AADSTS90009`, "requesting a token for itself") and the connection drops every \~60–90 minutes. It also gives MCP its own resource, separate from the app you use to sign in to the CIPP portal. You can flag more than one client for MCP.

**Which role applies.** It depends on how the token was obtained, not on which client was used:

| How the connector signs in | Runs with |
| --- | --- |
| A user signs in (PKCE, as Claude, ChatGPT and VS Code do, or a client secret, as Copilot Studio does) | **That user's own CIPP role** and its IP restrictions. The client's role is ignored. |
| The client's ID and secret only, no user (client credentials) | **The API client's role** and IP range. |

**Conditional Access.** Entra evaluates CA "cloud apps" against the _resource_ a sign-in is for, so scope any MCP Conditional Access to the **CIPP-MCP** resource app. One policy covers every connector, whichever client it uses. Scoping CA to the client app does **not** govern MCP sign-ins. Avoid **device-compliance** or **named-location** controls on CIPP-MCP: MCP tokens come from the AI provider's cloud IPs on an unmanaged device, so those will block the connector (MFA is already satisfied at the interactive sign-in and carried in the refresh). Device-compliance CA on your portal-login app is unaffected, because MCP is a separate resource.

</details>

<details>

<summary>Add a callback for an AI provider CIPP doesn't list</summary>

Add the provider's callback URL to the **MCP client app** (the API client you flagged MCP Access), not the CIPP-MCP resource app. Easiest: on the **API Clients** page → **MCP** tab, each MCP client has its own section with its connector URL and two callback boxes. Add the URL to the box that matches how the client signs in, then **Save Redirect URIs**:

- **Mobile & desktop callbacks** (public / PKCE): clients that redeem the authorization code without a secret: Claude, ChatGPT, VS Code, and CLI / loopback clients. This is almost every AI.
- **Web callbacks** (confidential): only clients that sign in with a client secret: Copilot Studio / Microsoft 365 Copilot agents.

CIPP writes each box to the matching Entra platform and always keeps the built-in provider callbacks. A callback under the wrong platform fails at the end of sign-in: a secret-less client under Web returns `AADSTS7000218` / `AADSTS9002327`, and a secret-based client under Mobile & desktop returns `AADSTS700025`. **Allow public client flows** stays **Yes** (Save to Azure sets this).

In Azure instead: **Entra ID → App registrations →** your MCP client app **→ Authentication → Add a platform →** pick **Mobile and desktop applications** (public / PKCE) or **Web** (secret-based) → paste the callback → **Configure**.

</details>

<details>

<summary>Troubleshooting the connection</summary>

**Asked to sign in again roughly every hour?** The AI needs the `offline_access` permission to receive a refresh token; current CIPP adds it automatically. After updating, disconnect and reconnect the connector once.

**AI asks for a client ID?** It doesn't support automatic registration. Enter the Application (Client) ID of the API client you flagged _MCP Access Allowed_ (the client, not the CIPP-MCP resource) and leave the secret blank.

**Every AI is a little different.** Check your provider's connector docs, or ask your AI directly: `Read the CIPP MCP setup instructions at https://docs.cipp.app/user-documentation/cipp/integrations/cipp-api#cipp-mcp and walk me through setting up the CIPP MCP integration. Give me the steps in order, the exact field values, the redirect/callback URL, and the ExecMCP endpoint URL.`

</details>

## Copilot Studio and Microsoft 365 Copilot Agents

Copilot Studio (and Microsoft 365 Copilot agents) is the one supported client that **can't** use the automatic, no-client-ID/no-secret flow above. The Power Platform connector behind Copilot Studio signs in as a confidential client with a **client secret**, which Microsoft Entra requires you to wire up by hand. It signs in as the **MCP client app** (the API client you flagged MCP Access), and CIPP pre-registers the callback for you when you run **Save to Azure**. You just supply the client ID, secret, and scopes in Copilot Studio's wizard.

{% hint style="info" %}
Do the [#cipp-mcp](cipp-api.md#cipp-mcp "mention") steps first (Enable MCP → create the MCP client → **Save to Azure**). Keep the **MCP client's Application (Client) ID** and its **secret** handy. If you didn't save the secret, reset it with **Actions → Reset Application Secret**.

Copilot Studio still signs each user in, so every call runs with **that user's own CIPP role**, not the client's role. Everyone who uses the agent needs a CIPP role that covers the tools it calls; otherwise they get "the user does not have the required permission".
{% endhint %}

{% stepper %}
{% step %}

### Add the MCP server in Copilot Studio

In your agent: **Tools → Add a tool → Model Context Protocol**. Set:

| Field                                | Value                                                                                                             |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| **Server name / description**        | Anything descriptive. The description drives whether the agent picks the tools, so write it like an API docstring. |
| **Streamable endpoint (Server URL)** | `https://<your-cipp-api-url>/api/ExecMCP`                                                                         |
| **Authentication**                   | **OAuth 2.0 → Manual**                                                                                            |

{% endstep %}

{% step %}

### Fill the Manual OAuth fields

| Field                 | Value                                                                            |
| --------------------- | ------------------------------------------------------------------------------- |
| **Client ID**         | The **MCP client's** Application (Client) ID (the API client flagged MCP Access).            |
| **Client secret**     | That client's **secret**, not blank. Copilot Studio is a confidential client.               |
| **Authorization URL** | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize`           |
| **Token URL**         | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token`               |
| **Refresh URL**       | Same as the Token URL.                                                           |
| **Scopes**            | `https://<cipp-backend-host>/user_impersonation offline_access openid profile`  |

- `<tenant-id>` is your CIPP tenant ID (shown on the CIPP-API page).
- `<cipp-backend-host>` is CIPP's backend host: the `…azurewebsites.net` **Application ID URI** shown under **Expose an API** on the **CIPP-MCP** resource app registration. It's the host in the `scope=` of the sign-in challenge, **not** your vanity `cipp.app` domain.

{% hint style="warning" %}
**Keep `offline_access` in the Scopes field.** It's what makes Entra issue a refresh token; without it, Copilot Studio re-prompts users to sign in roughly every hour. When you enable MCP on the client, CIPP admin-consents `offline_access` on the MCP client app and pre-authorises the client on the **CIPP-MCP** resource app's `user_impersonation` scope, so a refresh token is issued and no consent prompt appears, even in tenants that disable user consent to applications. You don't need to grant consent by hand.
{% endhint %}

{% endstep %}

{% step %}

### Save, then close the redirect loop

Click **Create / Save**. Copilot Studio generates a **Redirect / callback URL**.

- If it's `https://global.consent.azure-apim.net/redirect`, CIPP already registered it on the MCP client app during Save to Azure, so there is nothing to do.
- If Copilot Studio shows a different (per-connector) URL, add it on the **API Clients** page → **MCP** tab: in that client's section, paste it into the **Web callbacks** box and **Save Redirect URIs**. (In Azure instead: your MCP client app → **Authentication → Add a platform → Web** → paste it → **Configure / Save**.)

{% hint style="warning" %}
For Copilot Studio the callback goes on the **Web** platform, the opposite of the other AI clients (which use **Mobile and desktop applications**). A secret-based sign-in from a Mobile/desktop registration fails with `AADSTS700025`; a callback that was never added fails with `AADSTS50011`.
{% endhint %}

{% endstep %}

{% step %}

### Connect and test

Click **Next → Create a new connection**, sign in with your Microsoft account and approve, then **Add to agent**. Ask the agent something like _"Using CIPP, list all my tenants."_ If the tools return data, you're done.

{% hint style="info" %}
If the agent ignores the server, the usual cause is a weak **Server description**. The orchestrator uses it to decide whether to call the tools at all. See [#scoping-copilot-tool-imports](cipp-api.md#scoping-copilot-tool-imports "mention") for staying within Copilot's tool limit.
{% endhint %}

{% endstep %}
{% endstepper %}

## Scoping Copilot Tool Imports

CIPP advertises a small, fixed set of core tools rather than its whole catalogue. Older versions advertised every read-only endpoint at once, which pushes a client with a tool cap, Microsoft Copilot among them, past what it can import. If your connector still imports a long list of tools, recreate it against the current MCP URL.

Nothing is lost by that. The full read-only catalogue stays reachable through the core tools: your AI searches the catalogue, reads the schema of the tool it wants, and runs it.

To scope a connector further, add a query string to the MCP URL. The query is not part of the OAuth resource, so one CIPP instance can back several connectors, each scoped differently, with no extra Entra setup.

| Parameter                     | Effect                                                                          |
| ----------------------------- | ------------------------------------------------------------------------------- |
| `?tags=Identity,Exchange`     | Only tools in those top-level CIPP categories.                                  |
| `?tools=ListUsers,ListGroups` | An explicit allow list of tool names.                                           |
| `?first=70`                   | Caps the catalogue at the first 70 tools. `?limit=70` does the same.            |

{% hint style="warning" %}
A misspelt tag matches nothing, and the connector comes up advertising zero tools with no error in the client. If a connector suddenly has nothing to offer, check the category spelling first.
{% endhint %}

## Pre Version 7.1 Self-Hosted Deployments

#### Assign the “Contributor” Role to the Function App

If you're self-hosting and running your own Azure Function App, you'll need to grant it proper access:

{% stepper %}
{% step %}
#### Go to [Azure Portal](https://portal.azure.com).
{% endstep %}

{% step %}
#### Open the resource group hosting CIPP.
{% endstep %}

{% step %}
#### Select the **Function App** (not an offloaded app).
{% endstep %}

{% step %}
#### Navigate to **Access control (IAM)** > **+ Add** > **Add role assignment**.
{% endstep %}

{% step %}
#### Click on Privileged administrator roles.
{% endstep %}

{% step %}
#### Choose:

* **Role:** Contributor
* **Assign access to:** User, group, or service principal
* **Select:** The CIPP Function App identity

{% hint style="info" %}
The **Contributor** role should allow the identity to create and manage all types of Azure resources but does not allow them to grant access to others.

In the **Select** field and type `cipp`. As you begin typing, the list of options will narrow, and you should see the Managed Identity for your Function App.
{% endhint %}
{% endstep %}

{% step %}
#### Click **Save.**
{% endstep %}
{% endstepper %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

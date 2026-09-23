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
      2. Select the API Client from the list.
   3. Ensure that you Enable the client in order to save it to the Function App authentication settings.
   4. Optionally set the [#custom-roles](../../../setup/setting-up-cipp/roles.md#custom-roles "mention") and Allowed IP Ranges for additional security.
   5. Select if you want MCP Access Allowed for this client. Enabling MCP Access converts this client into the MCP resource app and it can no longer be used as a normal API client. Only one client per tenant can hold this role, MCP Access is only supported on the latest CIPP infrastructure. See [#enable-the-mcp-feature](cipp-api.md#enable-the-mcp-feature "mention") for more information.
   6. Submit the form to create the client. Remember to copy the Application secret to a secure location.
3. Once you have the API Client(s) configured, click Actions > Save to Azure, this updates the Function App authentication settings with the new Client IDs.

{% hint style="info" %}
The IP Range list supports both IPv4 and IPv6 addresses as standalone IP addresses or in CIDR Notation (for example 12.34.56.78/24 or 1.1.1.1).
{% endhint %}

{% hint style="info" %}
Custom Roles will limit which API endpoints each API Client can access. This can be used to limit all API calls to read only for example.
{% endhint %}

## API Egress

{% hint style="info" %}
Visible to SuperAdmins only. The card is hidden entirely on instances where egress accounting isn't enabled, such as most self-hosted deployments.
{% endhint %}

At the top of the CIPP-API page, on hosted instances with egress accounting enabled, a card shows how much data your API clients have served today against the instance's daily cap, with a per-client trend you can switch between 24h, 3d and 7d windows. The API Client table below it also gets an **EgressToday** column with each client's own total for today.

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

{% hint style="info" %}
**No client ID or secret needed.** CIPP publishes its OAuth details at a standard discovery address, so supported AI clients configure themselves from the MCP URL alone. Going forward, MCP is only supported on CIPP's latest infrastructure.
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
| **Role**               | `Readonly` (recommended), or a custom read role. This becomes what the AI can do. The role must not carry its own IP restriction, for the same reason the client's IP range has to be `Any`. |
| **IP range**           | `Any`. The connector calls in from your AI provider's servers, so you can't pin it to your office IPs. |
| **Enable this client** | On                                                                                               |
| **MCP Access Allowed** | **On**                                                                                           |

{% endstep %}

{% step %}

### Save to Azure

Click **Actions → Save to Azure**. This does all the Entra/Azure configuration for you automatically, including the callback URLs of the AI providers CIPP supports out of the box:

- **Claude** (`claude.ai` and `claude.com` for legacy purposes)
- **ChatGPT** connectors
- **Visual Studio Code** / GitHub Copilot Chat
- **Copilot Studio** and Microsoft 365 Copilot agents
- Local desktop and CLI clients, via a loopback callback

The instance restarts. Give it up to \~60 seconds before connecting.

If your AI isn't in that list, add its callback URL yourself:

1. Open the [Azure portal](https://portal.azure.com/) → **Microsoft Entra ID** → **App registrations**.
2. Select **All applications** and open your MCP client app, the one you flagged _MCP Access Allowed_ (search by its name, or by its Application/Client ID).
3. Go to **Authentication**.
4. Under **Platform configurations**, click **Add a platform → Mobile and desktop applications** (or use the existing one if it's already listed).
5. Paste your provider's callback URL into **Custom redirect URIs**, then **Configure / Save**.

{% hint style="warning" %}
Use **Mobile and desktop applications**, not **Web** or **Single-page application**. AI providers redeem their sign-in code without a client secret, and Microsoft only allows that on this platform. Getting it wrong fails right at the end of sign-in with `AADSTS7000218` (Web) or `AADSTS9002327` (Single-page application).

Also make sure **Allow public client flows** is set to **Yes** under **Authentication → Advanced settings**; Save to Azure sets this for you.
{% endhint %}

{% endstep %}

{% step %}

### Add the Connector in Your LLM

Add CIPP as a custom connector in your AI and give it the MCP URL. That's all you need: no client ID and no secret. The URL is `https://<your-cipp-api-url>/api/ExecMCP` and can be found on the API page.

Click **Connect**. You'll be redirected to your normal Microsoft / CIPP sign-in, so log in and approve. Your LLM completes the connection and CIPP's read tools appear.

If your AI still asks for a client ID, it doesn't support automatic registration. Enter the Application (Client) ID of the API client you flagged _MCP Access Allowed_, and leave the secret empty.

{% hint style="info" %}
**Copilot Studio and Microsoft 365 Copilot agents are the exception.** They sign in as a confidential client with a **client secret** (not the secret-less flow above), so they need a manual setup. Follow [#copilot-studio-and-microsoft-365-copilot-agents](cipp-api.md#copilot-studio-and-microsoft-365-copilot-agents "mention") instead of this step.
{% endhint %}

{% hint style="warning" %}
If you tried this URL before and it failed, your AI may have cached that result and will keep failing even after everything is fixed. Claude does this. Reconnect using a slightly different URL, for example `https://<your-cipp-api-url>/api/ExecMCP?retry=1`, which the AI treats as a new server.
{% endhint %}

{% hint style="info" %}
Every AI has a slightly different setup. Please reference the docs for your provider on how to connect the CIPP MCP tooling. Alternatively, ask your AI directly how to connect to the MCP with a prompt like: `Read the CIPP MCP setup instructions at https://docs.cipp.app/user-documentation/cipp/integrations/cipp-api#cipp-mcp and walk me through how to set up and configure the CIPP MCP integration with my AI. Give me the steps in order, include the exact field values I need to set, the redirect/callback URL, and the format of the ExecMCP endpoint URL. Note anything I have to copy and store securely.`
{% endhint %}
{% endstep %}

{% step %}

### Verify

Ask your AI something like:

> _Using CIPP, list all my tenants._

If tools show up and return data, you're done.
{% endstep %}
{% endstepper %}

## Copilot Studio and Microsoft 365 Copilot Agents

Copilot Studio (and Microsoft 365 Copilot agents) is the one supported client that **can't** use the automatic, no-client-ID/no-secret flow above. The Power Platform connector behind Copilot Studio signs in as a confidential client with a **client secret**, which Microsoft Entra requires you to wire up by hand. CIPP still pre-registers the callback for you when you run **Save to Azure**. You just supply the client ID, secret, and scopes in Copilot Studio's wizard.

{% hint style="info" %}
Do the [#cipp-mcp](cipp-api.md#cipp-mcp "mention") steps first (Enable MCP → create the MCP client → **Save to Azure**). Keep the MCP client's **Application (Client) ID** and **secret** handy. If you didn't save the secret, reset it with **Actions → Reset Application Secret**.
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
| **Client ID**         | The MCP client's **Application (Client) ID**.                                    |
| **Client secret**     | That client's **secret**, not blank. Copilot Studio is a confidential client.    |
| **Authorization URL** | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/authorize`           |
| **Token URL**         | `https://login.microsoftonline.com/<tenant-id>/oauth2/v2.0/token`               |
| **Refresh URL**       | Same as the Token URL.                                                           |
| **Scopes**            | `https://<cipp-backend-host>/user_impersonation offline_access openid profile`  |

- `<tenant-id>` is your CIPP tenant ID (shown on the CIPP-API page).
- `<cipp-backend-host>` is CIPP's backend host: the `…azurewebsites.net` **Application ID URI** shown under **Expose an API** on the MCP client's app registration. It's the host in the `scope=` of the sign-in challenge, **not** your vanity `cipp.app` domain.

{% hint style="warning" %}
**Keep `offline_access` in the Scopes field.** It's what makes Entra issue a refresh token; without it, Copilot Studio re-prompts users to sign in roughly every hour. CIPP admin-consents `offline_access` on the MCP client's app registration for you when you enable MCP on the client, so a refresh token is issued even in tenants that disable user consent to applications: you don't need to grant consent by hand.
{% endhint %}

{% endstep %}

{% step %}

### Save, then close the redirect loop

Click **Create / Save**. Copilot Studio generates a **Redirect / callback URL**.

- If it's `https://global.consent.azure-apim.net/redirect`, CIPP already registered it during Save to Azure, so there is nothing to do.
- If Copilot Studio shows a different (per-connector) URL, add it to the app registration: **Authentication → Add a platform → Web** → paste it → **Configure / Save**.

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

---

{% include "../../../../.gitbook/includes/feature-request.md" %}

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
3. Once you have the API Client(s) configured, click Actions > Save Azure Configuration, this updates the Function App authentication settings with the new Client IDs.

{% hint style="info" %}
The IP Range list supports both IPv4 and IPv6 addresses as standalone IP addresses or in CIDR Notation (e.g. 12.34.56.78/24 or 1.1.1.1).
{% endhint %}

{% hint style="info" %}
Custom Roles will limit which API endpoints each API Client can access. This can be used to limit all API calls to read only for example.
{% endhint %}

## Using an API Client

After creating your first API client, the page will update to include additional information that is necessary for your automation:

- Token URL: This URL is what you will need when authenticating your automation to your CIPP instance. See [setup-and-authentication.md](../../../api-documentation/setup-and-authentication.md "mention") for more information.
- Tenant ID: This is the tenant ID for the tenant used to authenticate CIPP where your CIPP service account lives, this may take 5-15 minutes before it updates from when you create your first API client and press save.
- API URL: This will be the base URL required for all post-authenticated calls. Note that most automation tools will require you to append `/api` to this base URL for successful responses.

## **Disabling an API Client**

1. Navigate to CIPP > Integrations and click on CIPP-API.
2. Find the API client in the table and click on the 3 dots in the Actions column > Edit.
3. Flip the Enabled switch off and click Submit.
4. At the top of the page, go to Actions and click Save Azure Configuration.

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

The CIPP MCP allows you to add CIPP to any AI you use and immediately talk to it in natural language. For example, you can ask "List all tenants with unassigned licenses" or "list all users for tenant MySpecialTenant.com". To set up the MCP, follow these instructions:

{% hint style="info" %}
**No client ID or secret needed.** CIPP publishes its OAuth details at a standard discovery address, so supported AI clients configure themselves from the MCP URL alone. Going forward, MCP is only supported on CIPPs latest infrastructure
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
| **Role**               | `Readonly` (recommended) — or a custom read role. This becomes what the AI can do.               |
| **IP range**           | `Any` — the connector calls in from Anthropic's servers, so you can't pin it to your office IPs. |
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

The instance restarts — give it up to \~60 seconds before connecting.

If your AI isn't in that list, add its callback URL yourself:

1. Open the [Azure portal](https://portal.azure.com/) → **Microsoft Entra ID** → **App registrations**.
2. Select **All applications** and open your MCP client app — the one you flagged _MCP Access Allowed_ (search by its name, or by its Application/Client ID).
3. Go to **Authentication**.
4. Under **Platform configurations**, click **Add a platform → Mobile and desktop applications** (or use the existing one if it's already listed).
5. Paste your provider's callback URL into **Custom redirect URIs**, then **Configure / Save**.

{% hint style="warning" %}
Use **Mobile and desktop applications** — not **Web** or **Single-page application**. AI providers redeem their sign-in code without a client secret, and Microsoft only allows that on this platform. Getting it wrong fails right at the end of sign-in with `AADSTS7000218` (Web) or `AADSTS9002327` (Single-page application).

Also make sure **Allow public client flows** is set to **Yes** under **Authentication → Advanced settings**; Save to Azure sets this for you.
{% endhint %}

{% endstep %}

{% step %}

### Add the Connector in Your LLM

Add CIPP as a custom connector in your AI and give it the MCP URL — that's all you need, no client ID and no secret. The URL is `https://<your-cipp-api-url>/api/ExecMCP` and can be found on the API page.

Click **Connect**. You'll be redirected to your normal Microsoft / CIPP sign-in — log in and approve. Your LLM completes the connection and CIPP's read tools appear.

If your AI still asks for a client ID, it doesn't support automatic registration. Enter the Application (Client) ID of the API client you flagged _MCP Access Allowed_, and leave the secret empty.

{% hint style="warning" %}
If you tried this URL before and it failed, your AI may have cached that result and will keep failing even after everything is fixed — Claude does this. Reconnect using a slightly different URL, for example `https://<your-cipp-api-url>/api/ExecMCP?retry=1`, which the AI treats as a new server.
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

## Scoping Copilot Tool Imports

By default CIPP exposes 5 tools; older versions used to expose over 70 tools, which is the limit for copilot please switch over to the new model to allow access for limited tools such as Microsoft Copilot.

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

---
description: API Authentication
---

# Setup & Authentication

## Setup

Before being able to utilize the CIPP API, you need to first configure an API client via [cipp-api.md](../user-documentation/cipp/integrations/cipp-api.md "mention"). Once that is completed, come back to this page. You'll need the integration page still open to reference the necessary fields below for authentication.

{% hint style="warning" %}
#### Self-Hosted Clients

If you originally deployed CIPP prior to v7.1 you will need to follow the instructions on [#pre-version-7.1-self-hosted-deployments](../user-documentation/cipp/integrations/cipp-api.md#pre-version-7.1-self-hosted-deployments "mention") before configuring your API client.
{% endhint %}

## Authentication

CIPP uses OAuth authentication to be able to connect to the API using your Application ID and Secret. You can use the PowerShell example below to connect to the API:

```powershell
$CIPPAPIUrl = "https://yourcippurl.com"
$ApplicationId = "your application ID"
$ApplicationSecret = "your application secret"
$TenantId = "your tenant id"

$AuthBody = @{
    client_id     = $ApplicationId
    client_secret = $ApplicationSecret
    scope         = "api://$($ApplicationId)/.default"
    grant_type    = 'client_credentials'
}
$token = Invoke-RestMethod -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" -Method POST -Body $AuthBody

$AuthHeader = @{ Authorization = "Bearer $($token.access_token)" }
Invoke-RestMethod -Uri "$CIPPAPIUrl/api/ListLogs" -Method GET -Headers $AuthHeader -ContentType "application/json"

```

{% hint style="info" %}
If you are making an OAuth connection with any 3rd party service, make use of the copyable fields on the [cipp-api.md](../user-documentation/cipp/integrations/cipp-api.md "mention") integration page indicated by a blue outline. You will also need the API Scope, get this from the CIPP-API Clients table by clicking the Actions three dots for the row you are configuring and selecting `Copy API Scope`.
{% endhint %}

## Rate Limits and Performance

Two limits apply to every call you make:

* **Timeout** — a single API action can run for up to 10 minutes.
* **Rate limit** — **100 requests per 10 second window**, per API client.

Both exist for the same reason. Your API calls run on the same backend that serves the CIPP interface, so no single caller should be able to tie up the workers your technicians depend on.

The rate limit behaves like this:

* **The window is fixed, not rolling.** Your allowance resets every 10 seconds rather than trickling back as individual requests age out, so the longest you ever wait after being throttled is the remainder of the current window.
* **Each API client gets its own budget.** A busy integration won't eat into the allowance of your other clients, or of the people working in the portal. Anything that runs hot is worth giving its own API client rather than sharing one across every automation.
* **Everything counts** — reads and writes, on every endpoint.
* **Requests over the limit are refused, not queued.** You get `HTTP 429 Too Many Requests` back immediately, with a `Retry-After` header telling you how many seconds to wait. Honor it and you'll land in a fresh window on the next attempt — most HTTP clients and SDKs can be configured to do this for you.

100 requests per 10 seconds works out to 10 per second sustained, which most integrations never approach. If yours does, it's nearly always a sign the same work can be done in far fewer calls. The three techniques below are how.

### Read from the reporting database

Many list endpoints accept `UseReportDB=true`:

```
GET /api/ListMailboxes?tenantFilter=contoso.onmicrosoft.com&UseReportDB=true
```

Instead of calling Microsoft live, CIPP hands back data it has already collected and stored. It's dramatically quicker, it doesn't spend the tenant's Microsoft API quota, and it doesn't queue up behind whatever the portal is doing.

The trade-off is freshness. CIPP refreshes this data automatically once a day, overnight, so it can be up to 24 hours old. That's ideal for inventory, reporting, dashboards and billing reconciliation. Use a normal live call when you need to see a change that was just made.

Endpoints that support `UseReportDB` today:

| Area | Endpoints |
| --- | --- |
| Identity | `ListGroups`, `ListMFAUsers` |
| Email & Exchange | `ListMailboxes`, `ListMailboxPermissions`, `ListMailboxRules`, `ListMailboxForwarding`, `ListCalendarPermissions`, `ListSharedMailboxAccountEnabled`, `ListHVEAccounts` |
| Endpoint | `ListApps`, `ListIntunePolicy`, `ListCompliancePolicies`, `ListAppProtectionPolicies`, `ListAssignmentFilters`, `ListIntuneScript`, `ListIntuneReusableSettings`, `ListCVEManagement` |
| Teams & SharePoint | `ListTeams`, `ListTeamsActivity`, `ListTeamsVoice`, `ListSites` |
| Security & Tenant | `ListMDEOnboarding`, `ListOAuthApps` |

{% hint style="info" %}
This list grows over time. The [endpoints.md](endpoints.md "mention") documentation is the authoritative source — if an endpoint lists a `UseReportDB` parameter, it supports this.
{% endhint %}

### Ask for every tenant in one call

Pass `tenantFilter=AllTenants` and you get a single response covering your whole estate, with every row tagged with the tenant it came from:

```
GET /api/ListMailboxes?tenantFilter=AllTenants&UseReportDB=true
```

For an MSP with 300 tenants, that's one request instead of three hundred — and comfortably inside your rate limit rather than five minutes of careful pacing.

{% hint style="warning" %}
Pair `AllTenants` with `UseReportDB=true` wherever you can. On endpoints without reporting database support, `AllTenants` still has to query every tenant live, so the call is slow and heavy even though it's only one request.
{% endhint %}

### Batch your Graph reads

When you need live data that CIPP doesn't have a purpose-built endpoint for, `POST /api/ListGraphBulkRequest` lets you send many Microsoft Graph reads as one call:

```json
{
  "tenantFilter": "contoso.onmicrosoft.com",
  "requests": [
    { "id": "users",   "method": "GET", "url": "/users?$top=999" },
    { "id": "groups",  "method": "GET", "url": "/groups?$top=999" },
    { "id": "devices", "method": "GET", "url": "/devices?$top=999" }
  ]
}
```

Each result comes back labelled with the `id` you gave it. Only `GET` requests are batched.

### Rules of thumb

* Fetch a whole list once and filter it on your side, rather than calling CIPP once per user, device or mailbox.
* Cache results in your own tooling. An automation polling every 15 minutes against data that only refreshes daily is making 96 identical calls a day.
* Schedule large syncs outside your working hours.
* Treat `429` as a normal operating condition rather than an error. Wait for the `Retry-After` period and carry on.

{% hint style="info" %}
Heavy sustained use can still slow the portal down even while you stay under the rate limit, since both share the same backend. These patterns are the difference between an integration nobody notices and one that generates support tickets.
{% endhint %}

## Endpoint documentation

{% content-ref url="endpoints.md" %}
[endpoints.md](endpoints.md)
{% endcontent-ref %}

## CIPP API PowerShell Module

You can install the CIPP API PowerShell module using PowerShell 7.x. The module takes care of all the authentication for you.

```powershell
Install-Module -Name CIPPAPIModule
```

You will first need to set your CIPP API Details using the following command:

```powershell
Set-CIPPAPIDetails -CIPPClientID "YourClientIDGoesHere" -CIPPClientSecret "YourClientSecretGoesHere" -CIPPAPIUrl "https://your.cipp.apiurl" -TenantID "YourTenantID"
```

You can then test its working

```powershell
Get-CIPPLogs
```

Further documentation for the module and each of its available functions can be found [here](https://github.com/BNWEIN/CIPPAPIModule/).

{% hint style="info" %}
This module is created and maintained by a community member. With CIPP's rapid development cycle, the module can be expected to lag behind in adding new endpoints. For those, it is recommended to use the command `Invoke-CIPPRestMethod`.
{% endhint %}

## Common Issues

1. If you are calling CIPP from an external automation platform (e.g., n8n, Rewst, Power Automate), make sure your base URL includes the `/api` path (e.g., `https://your-cipp-domain.com/api`). Direct API calls need to target the Azure Functions backend, not the static frontend — without `/api`, your requests will hit the web interface and return HTML instead of the expected JSON responses
2.  If you receive 400 (Bad Request) errors when first authenticating or testing your CIPP API connection (e.g. `Invoke-CIPPRestMethod: Response status code does not indicate success: 400 (Bad Request)`) your CIPP API app registration may be missing an Application ID URI.

    To fix this, go to **Microsoft Entra ID → App registrations** in your tenant and open the app registration for your CIPP API (not a separate client registration, unless your setup uses one). Navigate to **Expose an API**. If the **Application ID URI** field at the top is empty, click **Add**. Azure will auto-suggest a URI in the format `api://{application-id}`. The default is fine, no need to customize it. Click **Save**.

    If your setup requires a custom scope (e.g., `access_as_user`), you may also need to add one under **Expose an API → Add a scope** and then grant that scope as an API permission on the client side.

    After making changes, wait a minute or two before retrying authentication since propagation isn't always instant. If the error persists, try re-consenting to the app permissions.

{% include "../../.gitbook/includes/feature-request.md" %}

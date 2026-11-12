# External CSP

The External CSP integration connects CIPP to any CSP distributor that implements the CIPP External CSP API. Once configured, you can purchase licences while creating users, buy new subscriptions, adjust subscription quantities and cancel subscriptions from within CIPP.

This page has two parts. The first is for MSPs configuring the integration. The second, [For CSP Providers](external-csp.md#for-csp-providers), is the specification a distributor implements so that CIPP can talk to it.

{% hint style="warning" %}
External CSP is in beta and is turned off by default. To use it, enable **External CSP Integration (Beta)** under **CIPP > Application Settings > Features**. The integration does not appear on the Integrations page until the feature is on, and turning the feature off stops CIPP making any calls to your distributor.
{% endhint %}

{% hint style="info" %}
External CSP and [Sherweb](sherweb.md) cannot be enabled at the same time. CIPP uses one CSP provider for licence purchasing, and saving is refused while both are switched on.
{% endhint %}

{% hint style="warning" %}
External CSP connects CIPP to an API that your distributor builds and runs. CyberDrain does not support an individual distributor's integration unless that distributor holds a support contract with CyberDrain. For problems with credentials, the catalog, orders or subscriptions, contact your distributor first, and ask them whether their integration is supported.
{% endhint %}

## Prerequisites

Your distributor must support the CIPP External CSP API and give you:

* Six URLs, one for each call CIPP makes: test, catalog, subscriptions, new order, quantity change and cancel.
* Credentials, and which authentication method they expect.

Every customer tenant you want to manage must already exist as a customer at the distributor. CIPP identifies customers by their Microsoft tenant ID, so there is no tenant mapping to maintain in CIPP.

## Configuring the Integration in CIPP

{% stepper %}
{% step %}
#### Enable the integration

Turn on **Enable Integration**. The remaining fields stay disabled until it is on.
{% endstep %}

{% step %}
#### Choose the authentication method

Select the method your distributor requires under **Authentication**, then enter the credential in **Authentication Secret**. See [Authentication](external-csp.md#authentication) for what each method sends.
{% endstep %}

{% step %}
#### Enter the URLs

Enter the six URLs supplied by your distributor. Each must start with `https://`. If you later change any of these URLs, enter the **Authentication Secret** again in the same save; CIPP does not send a stored secret to a new address.
{% endstep %}

{% step %}
#### Restrict purchasing (optional)

Use **Select CIPP roles that are allowed to purchase licenses** to limit which custom roles may buy, change or cancel subscriptions. Leaving it empty places no restriction.
{% endstep %}

{% step %}
#### Save and test

Select **Submit** to save, then select **Test**. CIPP calls the distributor's test URL with your credentials; a green banner confirms they are accepted, and a red banner shows the reason the distributor gave.
{% endstep %}
{% endstepper %}

## Settings

| Setting                                                 | Description                                                                                                                              |
| ------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Enable Integration                                      | Turns the integration on. Cannot be saved while Sherweb is also enabled.                                                                 |
| Authentication                                          | How CIPP authenticates: API Key Header, Bearer Token, Basic Auth, or Custom Headers (JSON).                                              |
| API Key Header Name                                     | The header that carries the API key. Only appears for API Key Header. Defaults to `x-api-key` when left empty.                           |
| Basic Auth Username                                     | The username for Basic Auth. Only appears for Basic Auth.                                                                                |
| Authentication Secret                                   | The API key, bearer token, Basic Auth password, or custom headers JSON, depending on the method. Stored securely and masked once saved.  |
| Test URL (GET)                                          | Confirms the credentials are valid. Called by the **Test** button.                                                                       |
| Catalog URL (GET)                                       | Returns the products a customer can buy.                                                                                                 |
| Subscriptions URL (GET)                                 | Returns a customer's current subscriptions.                                                                                              |
| New Order URL (POST)                                    | Places an order for a product the customer does not yet hold.                                                                            |
| Quantity Change URL (POST)                              | Changes the quantity of an existing subscription.                                                                                        |
| Cancel URL (POST)                                       | Cancels one or more subscriptions.                                                                                                       |
| Select CIPP roles that are allowed to purchase licenses | Restricts subscription changes to CIPP users holding one of the selected custom roles. Leave empty to allow anyone with the permission.  |

{% hint style="warning" %}
The role restriction applies to subscription changes made through CIPP by a signed-in user or an API client. It does not apply to changes made by scheduled tasks, which run without a caller identity.
{% endhint %}

## Purchasing and Managing Licences

When adding or editing a user, selecting a licence with no available seats reveals **0 Licences available. Purchase new licence?**. Enabling it lets you pick one of the customer's existing subscriptions to add a seat to, and CIPP assigns the licence to the user once it becomes available. Where your distributor identifies which Microsoft licence each subscription provides, the list is narrowed to the matching subscriptions and a single match is selected for you; otherwise match the subscription by name.

The Add Subscription page purchases a new subscription from the distributor's catalog, and requires you to confirm that the purchase is made under your terms with the distributor.

The [CSP License Management](../../tenant/administration/csp-license-management/README.md) page carries row actions for existing subscriptions.

| Action                      | Description                                                         |
| --------------------------- | ------------------------------------------------------------------- |
| Increase licence count by 1 | Adds a single seat to the subscription immediately.                 |
| Decrease licence count by 1 | Removes a single seat from the subscription immediately.            |
| Increase licence count      | Adds a chosen number of seats to the subscription immediately.      |
| Decrease licence count      | Removes a chosen number of seats from the subscription immediately. |
| Cancel Subscription         | Cancels the subscription entirely.                                  |

A decrease that would leave a subscription with no seats is refused; use **Cancel Subscription** instead.

{% hint style="info" %}
External CSP is more limited than the [Sherweb](sherweb.md) integration. Scheduling a decrease at renewal, order status tracking and automated migrations are available with Sherweb only.
{% endhint %}

## For CSP Providers

This section is the specification for distributors. Implement the six endpoints below and give your partners the URLs and credentials; no code change or approval is needed in CIPP.

Every partner uses the same request and response format. CIPP does not support per-provider variations, so an endpoint that deviates from this specification will not work.

{% hint style="warning" %}
An integration built from this specification is unsupported by default. CSP providers that want to validate their integration and receive support, updates, and notifications of changes from CyberDrain must contact [vendors@cyberdrain.com](mailto:vendors@cyberdrain.com) to arrange a support contract.
{% endhint %}

### General Rules

* All URLs must be `https://`. You choose the paths; the partner enters each full URL.
* Customers are identified by `tenantId` on every call except the test endpoint, the customer's Microsoft Entra tenant ID (a GUID). Resolve it to your own customer record. CIPP never sends your internal customer identifier.
* The partner is identified by the credential. One credential must only be able to act on that partner's customers.
* Requests and responses are JSON (`Content-Type: application/json`).
* List responses are a bare JSON array, not wrapped in an object. Return `[]` when there is nothing to list.
* Any `2xx` status means success. CIPP ignores the body of a successful `POST`.
* Calls are synchronous. CIPP does not poll for order status and does not retry a failed call.

### Authentication

The partner chooses one of four methods in CIPP. Support at least one and tell your partners which.

| Method                | What CIPP sends on every request                                                                      |
| --------------------- | ----------------------------------------------------------------------------------------------------- |
| API Key Header        | The key in a header named by the partner, `x-api-key` by default.                                     |
| Bearer Token          | `Authorization: Bearer <token>`                                                                       |
| Basic Auth            | `Authorization: Basic <base64 of username:password>`                                                  |
| Custom Headers (JSON) | Every header in a JSON object the partner enters, for example `{"x-partner-id":"…","x-api-key":"…"}`. |

Credentials are static. CIPP does not perform an OAuth token exchange, so a bearer token must be long-lived.

### Errors

Return a non-`2xx` status to refuse a request, with a JSON body containing a `message`:

```json
{ "message": "This subscription is in its commitment term and cannot be decreased until 1 December." }
```

CIPP shows `message` to the technician as the reason for the failure, so write it for a person. Without a `message`, the technician only sees the HTTP status.

### Test

`GET <Test URL>`

Confirms that the URL is reachable and the credentials are valid. CIPP calls it when the partner selects **Test** on the integration page. It carries the same authentication as every other call and nothing else: no `tenantId`, no query string and no body.

This endpoint is required. Return any `2xx` when the credentials are valid; CIPP ignores the body. Return `401` or `403` with a `message` when they are not:

```json
{ "message": "This API key has been revoked." }
```

Validate the credential the same way your other endpoints do, so that a passing test means the other calls will be accepted. Do not require a customer to exist: a partner runs the test before placing any order.

### Tenants With No Relationship

CIPP may call you for tenants that are not your customers. A partner may manage tenants in CIPP that buy through another distributor or directly from Microsoft, and may manage its own tenant there too.

* **Catalog and subscriptions** return `200` with `[]`. A catalog that ignores `tenantId` returns the full catalog as usual. An empty list shows the technician an empty report rather than an error.
* **New order, quantity change and cancel** are refused with a non-`2xx` status and a `message` that says the tenant is not a customer and what to do about it, for example `"This tenant has no reseller relationship with Contoso Distribution. Create the customer in the partner portal first."`

Use `401` or `403` only for a credential that is invalid or not permitted, so a refusal about the tenant is not mistaken for a credential problem.

### Catalog

`GET <Catalog URL>?tenantId=<tenant GUID>`

Returns the products that can be bought. If your URL already contains a query string, `tenantId` is appended to it.

CIPP always sends `tenantId`. Use it if your catalog varies by customer, for example education, nonprofit or government eligibility, or per-customer price lists. Otherwise ignore it and return your full catalog.

Return only Microsoft 365 licence products where you can. CIPP manages Microsoft 365 licensing, so other products you sell, such as Azure plans, backup, security tools or hardware, cannot be assigned to users from CIPP and only make the list harder to search. If you cannot filter them out, they still work; the technician simply sees more entries.

```json
[
  {
    "sku": "BP-ANNUAL-MONTHLY",
    "microsoftSkuId": "cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46",
    "name": "Microsoft 365 Business Premium",
    "description": "Annual commitment, billed monthly.",
    "billingCycle": "Monthly",
    "commitmentTerm": "Annual"
  }
]
```

| Field            | Required | Description                                                                                       |
| ---------------- | -------- | ------------------------------------------------------------------------------------------------- |
| `sku`            | Yes      | Your identifier for the product. CIPP sends it back unchanged when ordering.                      |
| `microsoftSkuId` | No       | The Microsoft licence this product provides. See [Matching Microsoft Licences](external-csp.md#matching-microsoft-licences). |
| `name`           | Yes      | Product name shown to the technician.                                                             |
| `description`    | No       | Shown when the product is selected. Plain text or simple HTML.                                    |
| `billingCycle`   | No       | Shown when the product is selected, for example `Monthly`.                                        |
| `commitmentTerm` | No       | Shown when the product is selected, for example `Annual`.                                         |

### Subscriptions

`GET <Subscriptions URL>?tenantId=<tenant GUID>`

Returns the customer's current subscriptions. As with the catalog, return only Microsoft 365 licence subscriptions where you can.

```json
[
  {
    "subscriptionId": "sub-000123",
    "sku": "BP-ANNUAL-MONTHLY",
    "microsoftSkuId": "cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46",
    "name": "Microsoft 365 Business Premium",
    "quantity": 15,
    "purchaseDate": "2026-01-15",
    "renewalDate": "2027-01-15",
    "billingCycle": "Monthly",
    "commitmentTerm": "Annual"
  }
]
```

| Field            | Required | Description                                                                              |
| ---------------- | -------- | ---------------------------------------------------------------------------------------- |
| `subscriptionId` | Yes      | Your identifier for the subscription. CIPP sends it back for quantity changes and cancels. |
| `sku`            | Yes      | The same value the catalog uses for this product.                                        |
| `microsoftSkuId` | No       | The Microsoft licence this subscription provides. See [Matching Microsoft Licences](external-csp.md#matching-microsoft-licences). |
| `name`           | Yes      | Product name shown in the report.                                                        |
| `quantity`       | Yes      | Current seat count, as a whole number.                                                   |
| `purchaseDate`   | No       | ISO 8601 date.                                                                           |
| `renewalDate`    | No       | ISO 8601 date.                                                                           |
| `billingCycle`   | No       | Shown in the report.                                                                     |
| `commitmentTerm` | No       | Shown in the report.                                                                     |

CIPP calls this endpoint before every purchase or quantity change and looks for a subscription whose `sku` matches. Return at most one active subscription per `sku` for a customer; if several match, CIPP acts on the first.

### Matching Microsoft Licences

Your `sku` is your own identifier and means nothing to Microsoft 365. To let CIPP connect a subscription to the licence it provides, include `microsoftSkuId`: the Microsoft `skuId` GUID for the product, as returned by Microsoft Graph `subscribedSkus` and listed in Microsoft's [product names and service plan identifiers](https://learn.microsoft.com/entra/identity/users/licensing-service-plan-reference) reference. For example, Microsoft 365 Business Premium is `cbdc14ab-d96c-4c30-b9f4-6ada7cdc1d46`.

The field is optional but strongly recommended on subscriptions. When a technician buys a seat while creating or editing a user, CIPP uses it to:

* Hide subscriptions that provide a different licence from the one being assigned.
* Select the subscription automatically when exactly one matches.

Several of your products can share one `microsoftSkuId`, for example monthly and annual terms of the same licence. CIPP then lists all of them and the technician chooses. Subscriptions without the field are always listed, and the technician matches them by name.

### New Order

`POST <New Order URL>`

Sent when the customer has no subscription for the chosen `sku`.

```json
{
  "tenantId": "11111111-2222-4333-8444-555555555555",
  "sku": "BP-ANNUAL-MONTHLY",
  "quantity": 5,
  "orderedBy": "CIPP"
}
```

| Field       | Description                                         |
| ----------- | --------------------------------------------------- |
| `tenantId`  | The customer's Microsoft Entra tenant ID.           |
| `sku`       | A `sku` from your catalog.                          |
| `quantity`  | Number of seats to buy, 1 or more.                  |
| `orderedBy` | Always `CIPP`. Identifies the source of the order.  |

### Quantity Change

`POST <Quantity Change URL>`

Sent when the customer already has a subscription for the `sku`. `quantity` is the new total, not the difference.

```json
{
  "tenantId": "11111111-2222-4333-8444-555555555555",
  "subscriptionId": "sub-000123",
  "sku": "BP-ANNUAL-MONTHLY",
  "quantity": 17
}
```

| Field            | Description                                                |
| ---------------- | ---------------------------------------------------------- |
| `tenantId`       | The customer's Microsoft Entra tenant ID.                  |
| `subscriptionId` | The `subscriptionId` from your subscriptions response.     |
| `sku`            | The subscription's `sku`.                                  |
| `quantity`       | The new total seat count, 1 or more.                       |

CIPP does not know your commitment rules. If a decrease is not allowed, for example outside the cancellation window of a committed term, refuse it with an error `message` that explains when it will be allowed.

### Cancel

`POST <Cancel URL>`

```json
{
  "tenantId": "11111111-2222-4333-8444-555555555555",
  "subscriptionIds": ["sub-000123"]
}
```

| Field             | Description                                                |
| ----------------- | ---------------------------------------------------------- |
| `tenantId`        | The customer's Microsoft Entra tenant ID.                  |
| `subscriptionIds` | One or more `subscriptionId` values to cancel.             |

### Provisioning Time

When a technician buys a licence while creating or editing a user, CIPP places the order and then assigns the licence to the user on its next scheduled run, about 15 minutes later. The seat needs to be available in the customer's Microsoft 365 tenant by then, or the assignment fails and the technician has to assign it manually.

### Checklist

* All six endpoints are reachable over `https://`.
* The test endpoint returns `2xx` for a valid credential without needing a tenant, and `401` or `403` for an invalid one.
* Catalog and subscriptions return `[]`, not an error, for a tenant that is not your customer.
* Orders and changes for a tenant that is not your customer are refused with a `message`.
* `401` and `403` are used only for credential problems.
* The catalog and subscriptions responses contain only Microsoft 365 licence products where possible.
* `sku` values match between the catalog and subscriptions responses.
* Subscriptions carry `microsoftSkuId` wherever the product is a Microsoft 365 licence.
* At most one active subscription is returned per `sku` per customer.
* Refusals return a non-`2xx` status with a `message`.
* A credential can only read and change its own partner's customers.

{% include "../../../../.gitbook/includes/feature-request.md" %}

# Add Subscription

This page purchases a new CSP subscription for the selected tenant through Sherweb. Choose a SKU from the catalog, set the quantity, confirm you accept the terms, and submit.

{% hint style="danger" %}
Submitting this form places a real order with Sherweb and you will be billed for it. There is no draft or approval step, and the purchase cannot be undone from CIPP. To reduce or remove a subscription afterwards, use the actions on the CSP Licenses Report.
{% endhint %}

## Fields

| Field                             | Description                                                                                                                                                             |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Available SKUs for `<tenant>`     | The SKU to purchase, listed from the Sherweb catalog available to that tenant. Each entry shows the product name followed by its SKU. Required.                       |
| Quantity of licenses to purchase. | How many licenses to buy. Must be at least 1. Required.                                                                                                                 |
| Terms and conditions confirmation | Confirms you understand the license will be purchased according to the terms and conditions for that SKU with Sherweb. Must be ticked before the form can be submitted. |

## Selected SKU Details

Once a SKU is chosen, a card appears summarizing it. Check this before submitting, particularly the commitment term, since it determines how long you are committed to paying for the licenses.

| Field           | Description                                                            |
| --------------- | ---------------------------------------------------------------------- |
| Name            | The product name and SKU, as shown in the selector.                    |
| Billing Cycle   | How often the subscription is billed, for example monthly or annually. |
| Commitment Term | The length of the commitment you are entering into.                    |
| Description     | Sherweb's description of the product.                                  |

{% hint style="warning" %}
Where the tenant has no Sherweb mapping, the SKU list returns empty rather than raising an error, so the selector will simply have nothing in it. If you see no SKUs at all, check that the Sherweb integration is enabled and that the tenant is mapped to a Sherweb customer in the integration settings, rather than assuming the catalog is empty.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

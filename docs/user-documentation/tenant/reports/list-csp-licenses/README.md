# Sherweb Licence Report

This report lists the CSP subscriptions Sherweb holds for the selected tenant, showing each product's SKU, purchase date, quantity, and renewal date. From here you can adjust licence counts up or down, schedule a reduction to take effect at the next renewal, or cancel a subscription outright.

Unlike the [README.md](../list-licenses/README.md "mention"), which reads licence data from the tenant itself, this page queries Sherweb's billing API directly. It therefore shows what you are being billed for rather than what is assigned in Microsoft 365, and the two will not always agree.

{% hint style="warning" %}
This page requires the Sherweb integration to be enabled, and the tenant to be mapped to a Sherweb customer in the integration settings. Where either is missing, the page reports that it cannot retrieve CSP licences rather than returning an empty table.
{% endhint %}

## Action Buttons

{% content-ref url="add-subscription.md" %}
[add-subscription.md](add-subscription.md)
{% endcontent-ref %}

## Table Details

| Column        | Description                                                                                                          |
| ------------- | -------------------------------------------------------------------------------------------------------------------- |
| Product Name  | The name of the CSP product the subscription provides.                                                               |
| Sku           | The product's stock keeping unit, the identifier used to reference the subscription when adjusting or cancelling it. |
| Purchase Date | The date the subscription was purchased.                                                                             |
| Quantity      | The number of licences currently on the subscription.                                                                |
| Renewal Date  | The date the subscription's commitment term next renews.                                                             |
| Term Info     | Details of the subscription's commitment term.                                                                       |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Increase licence count by 1</td><td>Purchases one additional licence for the selected subscription.</td><td>true</td></tr><tr><td>Decrease licence count by 1</td><td>Reduces the licence count for the selected subscription by one.</td><td>true</td></tr><tr><td>Increase licence count</td><td>Purchases a specified number of additional licences. You are asked how many to add.</td><td>true</td></tr><tr><td>Decrease licence count</td><td>Reduces the licence count by a specified number, which must be greater than zero.</td><td>true</td></tr><tr><td>Schedule decrease of 1 at next renewal</td><td>Schedules a reduction of one licence to run shortly before the renewal date. You can set how many days before renewal it runs, defaulting to three. The decrease only happens if at least one licence is unassigned at that time, otherwise it is skipped and nothing changes.</td><td>true</td></tr><tr><td>Cancel Subscription</td><td>Cancels the entire subscription.</td><td>true</td></tr></tbody></table>

{% hint style="danger" %}
These actions change what you are billed for and take effect against Sherweb immediately. There is no confirmation step beyond the prompt, and increases are purchases. Check the tenant's actual assignment counts on the [README.md](../list-licenses/README.md "mention") before reducing a subscription, since Sherweb does not know which licences are assigned in Microsoft 365.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

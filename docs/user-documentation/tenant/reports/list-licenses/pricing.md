# Pricing

The License Pricing tab lets you set the monthly price you pay for each licence. The [optimization.md](optimization.md "mention") tab uses these prices to calculate licence costs and potential savings. CIPP includes estimated prices to start with. A price you enter replaces the estimate and is labelled **Override**. Prices apply to all tenants in your CIPP instance.

Saved prices remain after you refresh the page. Each currency has its own prices, so switching back to a currency shows the prices you saved for it.

## Action Buttons

<details>

<summary>Currency</summary>

Select the currency you want to view or edit. Changing currency does not convert prices: a licence with a USD price may have no GBP price. The list includes currencies with estimated or saved prices. CIPP remembers your choice in this browser and uses it on the Optimization tab too.

</details>

<details>

<summary>Export pricing CSV</summary>

Downloads all licence prices for the selected currency as a CSV file. Open it in Excel, change the prices, then upload the edited file using **Import CSV**. Licences without a price are included with an empty price cell.

Keep these required columns: `Product_Display_Name`, `skuPartNumber`, `skuId`, `MonthlyPrice`, and `Currency`. The `skuId` identifies which licence to update. The optional `Source` column shows where the current price came from; changing it has no effect.

</details>

<details>

<summary>Import CSV</summary>

Uploads your edited CSV so you can change several prices at once. You review the changes before saving them.

{% stepper %}
{% step %}

### Edit the export

Choose **Export pricing CSV** and open the downloaded file in Excel. Change the values in the `MonthlyPrice` column and leave the other columns unchanged. Enter zero or a positive number, for example `19.25`, using a decimal point without a currency symbol or thousands separator. Save the file as **CSV UTF-8 (Comma delimited)**.
{% endstep %}

{% step %}

### Upload and review

In CIPP, select the same currency as the file. Choose **Import CSV**, then **Choose CSV**, and select your edited file.

CIPP checks every row. It reports missing required fields, invalid or unknown SKU IDs, currencies it does not support or that differ from the selected currency, prices that are not numbers or are below zero, and repeated rows for the same SKU and currency. If any row has an error, nothing is saved. Correct the errors in the file, save it, and choose it again.

The review shows only the prices you changed, with the licence name, SKU ID, old price, and new price. For example: Microsoft 365 Business Premium, GBP 18.10 to GBP 19.25. Prices you left unchanged keep their existing value and source.

A price cell can be blank only if the licence already has no price. To remove a saved price, use **Remove override** on the pricing page. Deleting a price from the CSV does not remove it from CIPP.
{% endstep %}

{% step %}

### Confirm the changes

Choose **Confirm** to save. If a current price has changed since you opened the review, CIPP asks you to upload the file again and review the latest prices.

CIPP shows how many prices were updated, left unchanged, or failed to save. The pricing table refreshes automatically. If some updates fail, the successful ones stay saved. Correct the reported problems and import the file again; prices already saved are skipped.
{% endstep %}
{% endstepper %}

</details>

## Table Details

| Column               | Description                                                                                                                                                            |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Product Display Name | The licence's product name.                                                                                                                                            |
| Sku Part Number      | The licence's part number, for example `O365_BUSINESS_PREMIUM`.                                                                                                        |
| Monthly Price        | The price per seat per month in the selected currency. Empty when the licence has no price in that currency.                                                           |
| Currency             | The currency of the price.                                                                                                                                             |
| Source               | Where the price comes from: **Override** for a price you set, **Estimate** for the estimate shipped with CIPP, or **Unknown** when there is no price in this currency. |
| Sku Id               | The licence's SKU identifier.                                                                                                                                          |

{% hint style="info" %}
An override always takes priority over the shipped estimate. Setting prices you actually pay, and pricing the licences marked **Unknown**, makes the figures on the Optimization tab more accurate, since a licence with no price is left out of its savings and plan suggestions.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Set / override price</td><td>Sets your own monthly price per seat for the licence, in the currency currently selected. The price replaces the shipped estimate for that currency only, and applies to every tenant.</td><td>true</td></tr><tr><td>Remove override</td><td>Removes your price for the licence in that currency after you confirm, so it falls back to the shipped estimate. Greyed out unless the row's source is <strong>Override</strong>.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}

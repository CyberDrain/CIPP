# Work from Anywhere

Reports each Intune-managed device's readiness to upgrade to the latest version of Windows, and shows which hardware requirement failed where a device does not qualify. The **Upgrade not eligible** filter narrows the table to devices Intune has assessed as not capable.

## Table Details

The properties returned are for the Graph resource type `userExperienceAnalyticsWorkFromAnywhereDevice`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-userexperienceanalyticsworkfromanywheredevice?view=graph-rest-beta#properties).

{% hint style="info" %}
Upgrade Eligibility summarizes the outcome as Capable, Not Capable, Upgraded or Unknown. The columns ending in Check Failed break that down: each is true where the device failed that particular requirement, so a device showing Not Capable can be traced to the RAM, storage, processor, TPM, Secure Boot or operating system check that caused it.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View in Intune</td><td>Opens the device in the Microsoft Intune admin center in a new tab.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
Devices only appear here once Endpoint Analytics has been enabled in the tenant and has collected enough data from them.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

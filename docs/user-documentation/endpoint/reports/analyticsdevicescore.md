# Analytics Device Score

Reports Endpoint Analytics scores for each device in the selected tenant. Endpoint Analytics rates the user experience a device delivers, combining startup performance, application reliability, battery health and remote work readiness into a single score, so a device performing badly can be found without working through each measure separately.

## Table Details

The properties returned are for the Graph resource type `userExperienceAnalyticsDeviceScores`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-userexperienceanalyticsdevicescores?view=graph-rest-beta#properties).

{% hint style="info" %}
Every score runs from 0 to 100, where a higher score is healthier. A score of -1 means that measure is not available for the device, usually because it has not reported enough data yet. Health Status summarizes the same picture as Meeting Goals, Needs Attention, Insufficient Data or Unknown.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View in Intune</td><td>Opens the device in the Microsoft Intune admin center in a new tab.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
Devices only appear here once Endpoint Analytics has been enabled in the tenant and has collected enough data. An empty report usually means Endpoint Analytics has not been turned on rather than that no devices qualify.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

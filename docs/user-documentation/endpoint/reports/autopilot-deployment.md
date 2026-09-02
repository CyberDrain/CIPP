# Autopilot Deployments

Reports each Autopilot deployment event recorded in the selected tenant, newest first, with how long each stage took and why a deployment failed. The **Failed Deployments** and **Successful Deployments** filters narrow the table to those outcomes.

## Filters

| Filter                 | Shows                                              |
| ---------------------- | -------------------------------------------------- |
| Failed Deployments     | Autopilot deployments that failed.                 |
| Successful Deployments | Autopilot deployments that completed successfully. |

## Table Details

The properties returned are for the Graph resource type `deviceManagementAutopilotEvent`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/intune-troubleshooting-devicemanagementautopilotevent?view=graph-rest-beta#properties).

{% hint style="info" %}
Deployment State is the overall outcome. Where a deployment failed, Enrollment Failure Details carries the reason, and the row flyout breaks the deployment into its stages: Device Setup Status and Account Setup Status show how each Enrollment Status Page phase ended, with Device Setup Duration and Account Setup Duration for the time each took. Deployment Total Duration is the whole thing, from enrollment through to the desktop.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Device in Intune</td><td>Opens the device in the Microsoft Intune admin center in a new tab.</td><td>false</td></tr><tr><td>View Deployment Details</td><td>Opens the Autopilot deployment overview in the Microsoft Intune admin center in a new tab.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
Intune retains Autopilot deployment events for a limited period, so a deployment that ran some time ago may no longer appear here even though the device is still enrolled.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

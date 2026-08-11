# Risk Detections

This report lists the risk detections Microsoft Entra ID Protection has raised, with the most recent first. Each row is a single detection rather than a user, so one account under investigation may appear several times with different detection types and timings.

## Table Details

The properties returned are for the Graph resource type `riskDetection`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/riskdetection?view=graph-rest-beta#properties).

{% hint style="info" %}
The **Location** column is a button rather than plain text. Selecting it opens a Location Details dialog plotting the detection on a map, with the city, state and country listed alongside, which is usually the quickest way to judge whether a detection is a genuine anomaly or the user traveling.
{% endhint %}

## Filters

| Filter                | Shows                                                                                                     |
| --------------------- | --------------------------------------------------------------------------------------------------------- |
| Users at Risk         | Detections still open and not yet acted on.                                                               |
| Confirmed Compromised | Detections an administrator has confirmed as a genuine compromise.                                        |
| Confirmed Safe        | Detections an administrator has marked as legitimate activity.                                            |
| Remediated            | Detections resolved by the user meeting a remediation requirement, such as a self-service password reset. |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Research Compromised Account</td><td>Opens the <a data-mention href="../administration/users/user/bec.md">bec.md</a> tab for the account the detection relates to, where the usual indicators of compromise are gathered in one place.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
Risk state is held against the user rather than the individual detection, so marking a user as safe or compromised in Entra ID Protection changes the state shown on every detection for that account. The [risky-users.md](../administration/risky-users.md "mention") page is where a user's overall risk is reviewed and dismissed.
{% endhint %}

{% hint style="warning" %}
Entra ID Protection needs Entra ID P2 licensing to report detections in full. Tenants without it see limited or no detection data, so an empty table means the feature is unavailable rather than that no risk was detected.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

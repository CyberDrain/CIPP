# MAA Requests

Lists the multi-admin approval requests raised in the selected tenant. Where an access policy protects a resource type, Intune does not apply a change immediately: it holds the change and records a request here until a second administrator approves it. This is where a change made from CIPP that appears to have done nothing ends up, along with the history of requests already decided.

{% hint style="warning" %}
Approval decisions cannot be made from CIPP. Intune rejects a decision from a GDAP delegated identity and from an application identity alike, and a requestor may never approve its own request, which CIPP always is. The decision has to come from an account signed in to the customer tenant that belongs to the approver group on the access policy, working under **Tenant administration > Multi Admin Approval > Received requests**.
{% endhint %}

## Action Buttons

<details>

<summary>Action in Intune</summary>

Explains why the decision cannot be made in CIPP and offers a link that opens the selected tenant in the Microsoft Intune admin center in a new tab.

</details>

## Table Details

| Column                | Description                                                                                                                                                                                                                                       |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Status                | Where the request has got to. `needsApproval` is still waiting on a decision. `approved`, `rejected`, `canceled` and `expired` are final, as is `completed`, which means the request was processed rather than that the change itself succeeded. |
| Operation             | The operation the change performs.                                                                                                                                                                                                                |
| Target                | The name of the object the change applies to.                                                                                                                                                                                                     |
| Operation Types       | The approval policy types the request has to satisfy before it can be decided.                                                                                                                                                                    |
| Request Justification | The justification recorded when the request was raised.                                                                                                                                                                                           |
| Request Date Time     | When the request was raised.                                                                                                                                                                                                                      |
| Expiration Date Time  | When the request stops being actionable. Requests expire three days after they are raised, and an expired request cannot be approved. The change has to be made again to raise a new one.                                                         |

The row flyout adds the approval justification recorded with the decision, the requestor and approver, and the request's identifier. Intune leaves the requestor and approver empty in practice, including for requests raised through Graph, which is why they are not columns.

The underlying properties are those of the Graph resource type `operationApprovalRequest`. For more information please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/intune-rbac-operationapprovalrequest?view=graph-rest-beta#properties).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

The table deliberately offers nothing else. Approving and rejecting are refused by Intune for the reasons above, and deleting a request is not offered because the request is the tenant's record of a pending decision: removing it would neither apply nor cancel the change behind it.

{% hint style="info" %}
Once a request is approved, a change CIPP raised is reapplied automatically. There is nothing to resubmit from this page.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

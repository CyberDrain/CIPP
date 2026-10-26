# Risky Users

This page lists the accounts Microsoft Entra ID Protection currently holds a risk assessment for, so a tenant's flagged users can be reviewed and cleared without opening the Entra portal. The table is sorted with the most recently updated risk first.

## Filters

| Filter           | Shows                                                                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Users at Risk    | Accounts whose risk is still open and has not been acted on.                                                                                     |
| Dismissed Users  | Accounts whose risk has been dismissed, either here or in the Entra portal.                                                                      |
| Remediated Users | Accounts whose risk was resolved by the user meeting a remediation requirement, such as a self-service password reset or a risky sign-in policy. |

## Table Details

The properties returned are for the Graph resource type `riskyUser`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/riskyuser?view=graph-rest-beta#properties).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Dismiss Risk</td><td>Marks the account's risk as dismissed, which tells Entra ID Protection the activity was legitimate and returns the account to a normal state.</td><td>true</td></tr><tr><td>Research Compromised Account</td><td>Opens the <a data-mention href="bec/case.md">case.md</a> tab for the account, where the usual indicators of compromise are gathered in one place.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
Dismissing a risk closes it without changing anything about the account. It does not reset a password, revoke a session or remove whatever caused the detection, so an account that really is compromised stays compromised with its warning cleared. Investigate before dismissing, and remediate through the [case.md](bec/case.md "mention") page or the Users list where the account turns out to be at risk.
{% endhint %}

{% hint style="info" %}
This page depends on Microsoft Entra ID Protection, which needs Entra ID P2 licensing. Tenants without it return no risk data, so an empty table means the feature is unavailable rather than that no user is at risk.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

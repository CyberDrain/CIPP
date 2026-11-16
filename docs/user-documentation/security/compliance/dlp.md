# DLP Policies

Data Loss Prevention policies detect sensitive content and control what people can do with it. Each policy sets a mode and a scope of workload locations, and holds one or more rules that describe what to look for and what to do about a match. This page lists the DLP policies in the selected tenant, shows how many rules each one carries, and lets you enable, disable, delete or capture them as reusable templates.

## Action Buttons

<details>

<summary>Deploy DLP Policy</summary>

Opens a drawer that creates a DLP policy in one or more tenants from a template or from parameters you supply yourself.

| Field | Description |
| ----- | ----------- |
| Select Tenants | The tenants to create the policy in. At least one is required, and you can pick several to deploy the same policy across a group of customers in one go. |
| Select a template (optional) | Picks a saved DLP policy template. Choosing one fills **Parameters (JSON)** with that template's stored settings, which you can then edit before deploying. |
| Parameters (JSON) | The policy settings as JSON. Required. A worked example is shown in the field until you type into it, covering the policy name, mode, workload locations and a nested `RuleParams` block for the rule created alongside the policy. |

</details>

## Table Details

| Column | Description |
| ------------- | ----------------------------------------------------------------------------------------------------- |
| Name          | The policy name.                                                                                      |
| Mode          | The policy's action and notification level. Values are listed below.                                   |
| Enabled       | Whether the policy is currently switched on.                                                          |
| Workload      | The Microsoft 365 workloads the policy covers, such as Exchange, SharePoint, OneDrive or Teams.        |
| Rule Count    | How many DLP rules belong to this policy. Counted by CIPP, so a policy with no rules shows zero here.  |
| Created By    | The account that created the policy.                                                                  |
| When Created UTC | When the policy was created, in UTC.                                                               |
| When Changed UTC | When the policy was last modified, in UTC.                                                         |

### Mode

| Value | Meaning |
| ----- | ------- |
| `Enable` | The policy is live and its rules are enforced. |
| `TestWithNotifications` | The policy is in test, taking no enforcement action, but users see policy tips and notifications. |
| `TestWithoutNotifications` | The policy is in test and silent. Matches are recorded, but nothing is enforced and users see nothing. |
| `Disable` | The policy is switched off. |
| `PendingDeletion` | The policy is on its way out and cannot be brought back into use. |

{% hint style="info" %}
The two test modes are the low risk way to introduce a policy to a tenant you do not know well: neither enforces anything, and they differ only in whether users are told. Move to `Enable` once you are satisfied with what the policy is matching.
{% endhint %}

The Extended Info flyout adds the policy comment and the individual workload location lists, so you can see exactly which mailboxes, sites and Teams a policy is scoped to.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Create template based on policy</td><td>Saves the selected policy as a DLP policy template so it can be redeployed to other tenants. Rules that use sensitivity labels need editing before they work in another tenant, as covered in <a data-mention href="dlp-templates.md#sensitivity-label-conditions">dlp-templates.md</a>.</td><td>false</td></tr><tr><td>Enable Policy</td><td>Switches the selected policy on. Greyed out when the policy is already enabled.</td><td>true</td></tr><tr><td>Disable Policy</td><td>Switches the selected policy off, leaving it in place but not enforcing. Greyed out when the policy is already disabled.</td><td>true</td></tr><tr><td>Delete Policy</td><td>Permanently removes the selected policy and the rules belonging to it.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}

---
description: Review all Conditional Access Policies per tenant
---

# CA Policies

This page lists the Conditional Access policies on the selected tenant, flattened into a single table so you can compare policies at a glance rather than opening each one. CIPP resolves the GUIDs Microsoft stores for users, groups, applications, roles, and named locations into display names, so the table reads as names rather than identifiers.

This page supports the All Tenants view. The first time you select it, CIPP queues a background collection across every tenant and shows a message asking you to check back in a few minutes. Results are cached for an hour, so subsequent loads are immediate.

## Action Buttons

<details>

<summary>Deploy Conditional Access Policy</summary>

Opens the deployment drawer, for pushing a template to a tenant. See [#deploying-a-policy](./#deploying-a-policy "mention") for the available options.

</details>

<details>

<summary>View Logs</summary>

Opens the Conditional Access entries from the CIPP [logs](../../../cipp/logs/ "mention"), covering policies, templates, and deployments.

</details>

### Deploying a Policy

Conditional Access policies reference users, groups, and named locations by GUID, and those GUIDs are tenant-specific. A template built in one tenant will not resolve correctly in another unless the references are translated, which is what most of the options below are for.

| Field                                                     | Description                                                                                                                      |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Tenant                                                    | The tenant to deploy to. Required.                                                                                               |
| Template                                                  | The CA template to deploy, drawn from list-template.                                                                             |
| Conditional Access Parameters                             | The raw policy JSON, populated from the selected template and editable before deployment.                                        |
| How should groups and users be handled?                   | Controls how user and group references are translated. See below.                                                                |
| Policy State                                              | Deploy the policy as enabled, disabled, or report only, or leave the template's own state unchanged.                             |
| Overwrite Existing Policy                                 | Replaces a policy of the same name in the target tenant rather than failing.                                                     |
| Disable Security Defaults if enabled when creating policy | Turns off Security Defaults in the target tenant, which otherwise blocks Conditional Access from taking effect.                  |
| Create groups if they do not exist                        | Creates any group named in the template that is missing from the target tenant. Only available when translating by display name. |

#### Translation modes

| Option                                    | Behavior                                                                                                                                                                                                                                                                                                                                                    |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Replace by display name                   | CIPP enumerates the target tenant's users and groups and swaps each display name in the template for the matching object's GUID in that tenant. Special tokens such as `All`, `None`, and `GuestOrExternalUsers` are left alone, and GUIDs already present pass through unchanged. This is the option to use for any template that came from another tenant. |
| Remove all exclusions, apply to all users | Strips every user and group include and exclude, scoping the policy to all users. Useful for tenant-wide baseline policies that should not depend on group membership.                                                                                                                                                                                       |
| Leave the groups and users as is          | Deploys the template verbatim, sending the original tenant's GUIDs unchanged. This only works where those exact identifiers already exist in the target tenant.                                                                                                                                                                                              |

{% hint style="info" %}
**Create groups if they do not exist** only applies alongside **Replace by display name**, and is disabled otherwise. Where a CIPP group template exists with the same display name, the group is created from that template, preserving group type and membership rules. Otherwise a basic security group is created. With the option off, a missing group causes the deployment to fail so you can create or rename it yourself first.
{% endhint %}

{% hint style="info" %}
Standards deploy Conditional Access templates using the display-name translation, which is why standards-driven deployments are portable across tenants without any extra configuration. Use a standard rather than this drawer when you want the policy re-applied automatically on drift.
{% endhint %}

## Table Details

CIPP flattens each policy's nested conditions into single columns and resolves identifiers to display names, so these columns do not map one-to-one onto the Graph resource.

| Column                  | Description                                                                     |
| ----------------------- | ------------------------------------------------------------------------------- |
| Tenant                  | The tenant the policy belongs to. Most useful in the All Tenants view.          |
| Display Name            | The name of the policy.                                                         |
| State                   | Whether the policy is enabled, disabled, or in report-only mode.                |
| Modified Date Time      | When the policy was last changed.                                               |
| Client App Types        | The client app types the policy applies to, for example browser or mobile apps. |
| Include Platforms       | Device platforms the policy targets.                                            |
| Exclude Platforms       | Device platforms excluded from the policy.                                      |
| Include Locations       | Named locations the policy targets, resolved to their names.                    |
| Exclude Locations       | Named locations excluded from the policy.                                       |
| Include Users           | Users the policy targets, resolved to display names.                            |
| Exclude Users           | Users excluded from the policy.                                                 |
| Include Groups          | Groups the policy targets, resolved to display names.                           |
| Exclude Groups          | Groups excluded from the policy.                                                |
| Include Applications    | Applications the policy targets, resolved to display names.                     |
| Exclude Applications    | Applications excluded from the policy.                                          |
| Grant Controls Operator | Whether the grant controls are combined with AND or OR.                         |
| Built In Controls       | The grant controls the policy requires, for example MFA or a compliant device.  |

{% hint style="info" %}
Where an identifier cannot be resolved, users, roles, and locations fall back to showing the raw GUID. Groups instead show **No Data**, which usually means the group has been deleted while the policy still references it.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Policy</td><td>Opens <a data-mention href="edit-ca-policy.md">edit-ca-policy.md</a> for editing.</td><td>false</td></tr><tr><td>Create template based on policy</td><td>Creates a CIPP template from the policy, making it available to deploy to other tenants. See below.</td><td>false</td></tr><tr><td>Change Display Name</td><td>Renames the policy.</td><td>false</td></tr><tr><td>Enable policy</td><td>Sets the policy to enabled. Only shown when the policy is not already enabled.</td><td>true</td></tr><tr><td>Disable policy</td><td>Sets the policy to disabled. Only shown when the policy is not already disabled.</td><td>true</td></tr><tr><td>Set policy to report only</td><td>Sets the policy to report only, so it logs what it would have done without enforcing anything. Only shown when the policy is not already in report-only mode.</td><td>true</td></tr><tr><td>Add service provider exception to policy</td><td>Adds an exclusion for your partner tenant's accounts, so the policy cannot lock you out of the customer tenant.</td><td>true</td></tr><tr><td>Delete policy</td><td>Deletes the policy from the tenant.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
The Extended Info flyout shows the policy's complete raw JSON, including conditions the table does not surface such as sign-in risk, user risk, roles, terms of use, and session controls.
{% endhint %}

## Template Creation

**Create template based on policy** saves a policy as a reusable template, which then appears in list-template.

Every property of the policy is captured. Inclusions and exclusions are stored in a form CIPP can translate on redeployment, and everything else carries across, including named locations, authentication strengths, and session controls.

{% include "../../../../../.gitbook/includes/feature-request.md" %}

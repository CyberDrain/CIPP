---
description: Define Privileged Identity Management role settings once and deploy them to every tenant (Roles & PIM page, second tab)
---

# PIM Templates

The **PIM Templates** tab of the Roles & PIM page lists the role settings templates. Besides building one by hand, the **Create template from role settings** action on the Roles & Assignments tab captures a role's current settings from a tenant into a new template; values below the secure floor are raised to the closest allowed value and every raise is reported. A PIM template describes how a set of Entra directory roles must behave in Privileged Identity Management: how long an activation may last, what an administrator has to prove and write down to activate, whether someone has to approve, how long eligible and active assignments may exist, and who is notified. The **PIM Role Settings Template** standard deploys a template to a tenant and reports drift from it.

## Action Buttons

{% content-ref url="add.md" %}
[add.md](add.md)
{% endcontent-ref %}

<details>

<summary>Browse Catalog</summary>

Opens a drawer listing the PIM role settings templates published in the community repositories you have configured, so you can bring one into CIPP.

{% hint style="info" %}
Be sure to check out [community-repos](../../../../tools/community-repos/ "mention") for more on setting up repositories.
{% endhint %}

</details>

## The secure floor

Templates are validated when they are saved and again every time the standard runs. A template that falls below CIPP's secure floor is refused with the list of problems; it is never silently adjusted.

| Setting                                   | Floor                                                       | Default  |
| ----------------------------------------- | ----------------------------------------------------------- | -------- |
| Maximum activation duration               | Must expire; at most 24 hours. Above 8 hours is allowed but logged as a warning. | 8 hours  |
| Activation requires                       | MFA, or a Conditional Access authentication context         | MFA      |
| Justification on activation               | Always required                                             | Required |
| Maximum eligible assignment duration      | Must expire; at most 1 year                                 | 1 year   |
| Maximum active assignment duration        | Must expire; at most 1 year                                 | 6 months |
| Justification when creating an assignment | Always required                                             | Required |
| Approval, ticket, notifications           | Optional                                                    | Off      |

Requiring active assignments to expire means administrators cannot create permanent active assignments in the Entra portal either once the template is deployed.

## Table Details

| Column                          | Description                                                                                      |
| ------------------------------- | ------------------------------------------------------------------------------------------------ |
| Template Name                   | The template's name.                                                                             |
| Role Scope                      | **PrivilegedRoles** (CIPP's privileged-roles list), **AllRoles**, or a **Custom** selection.     |
| Role Count                      | Number of roles in a custom selection.                                                           |
| Activation Max Duration         | The maximum lifetime an activated role stays active, as an ISO 8601 duration.                    |
| Activation Requires             | Whether activating the role requires MFA or a Conditional Access authentication context.         |
| Activation Requires Approval    | Whether activating the role needs an approver to sign off.                                       |
| Eligibility Max Duration        | The maximum lifetime an eligibility may be granted for, as an ISO 8601 duration.                 |
| Active Assignment Max Duration  | The maximum lifetime an active assignment may be granted for, as an ISO 8601 duration.           |
| Meets Secure Floor              | Whether the stored template still satisfies the floor. A template edited outside CIPP can fail this and will not be deployed. |
| Updated By                      | The account that last saved the template.                                                        |
| Updated Date                    | When the template was last saved.                                                                |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Template</td><td>Opens the template in the editor.</td><td>false</td></tr><tr><td>Save to GitHub</td><td>Uploads the template to a community repository you have write access to. Only shown when the GitHub integration is enabled.</td><td>false</td></tr><tr><td>Delete Template</td><td>Deletes the template. Tenants already configured from it keep their settings.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
Approvers are stored as group display names or user principal names and resolved in each tenant when the standard runs, so one template works across tenants. If none of the approvers exist in a tenant the template is not applied there and an error is logged.
{% endhint %}

{% include "../../../../../../.gitbook/includes/feature-request.md" %}

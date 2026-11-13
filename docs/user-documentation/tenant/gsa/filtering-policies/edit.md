# Edit Filtering Policy

Creates or edits a filtering policy in the selected tenant. Open it with **Add Policy** or **Edit Policy** on the Filtering Policies page. A new policy's name must not already be used in the tenant. Changes are written to the tenant when you save.

## Fields

| Field               | Description                                                                   |
| ------------------- | ----------------------------------------------------------------------------- |
| Name                | Required. Policy names are unique within a tenant.                            |
| When a rule matches | **Block** or **Allow** the traffic that matches any rule in the policy.       |
| Description         | Optional.                                                                     |

## Rules

The rules work as they do in a [filtering policy template](template.md). A policy needs at least one rule. When you save, rules that did not change are left alone, removed rules are deleted and new or changed rules are added.

If this policy was deployed from a template, the next deploy of that template puts the template's settings back.

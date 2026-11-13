# Compare CA Policies

Compare CA Policies puts two Conditional Access policies side by side and lists every setting where they differ. Each side can be a CIPP Conditional Access template or a policy as it is currently deployed in one of your tenants, so you can check a tenant's policy against the template it was deployed from, compare the same policy across two tenants, or compare two templates before choosing one for a baseline.

The comparison is the same one the Conditional Access drift standard runs. Users, groups, roles and named locations are compared by display name rather than object ID, so a policy that targets the "Admins" group in one tenant matches a template that targets a group of the same name. Identifiers, timestamps and other properties Entra manages itself are left out of the comparison.

Viewing this page needs the `Tenant.ConditionalAccess` read permission.

## Choosing What to Compare

The page presents two identical selectors, **Source A** and **Source B**. Each has a **Source Type** option that determines where its policy is read from, and the fields below it change to match. The two sources are independent, so a template can be compared with a tenant policy, two tenant policies with each other, or two templates.

### CIPP Template

Compares against a Conditional Access template stored in CIPP.

| Field           | Description                                                      |
| --------------- | ---------------------------------------------------------------- |
| Select Template | The CIPP Conditional Access template to use. Required.           |

When the other side is a tenant policy, the template is resolved for that tenant first: CIPP variables such as `%tenantname%` and custom variables take the values they would have on deployment, so they are not reported as differences. When both sides are templates, variables are shown as written. Named locations in a template are matched to the names recorded when the template was captured.

### Tenant Policy

Compares against a policy as it is currently deployed in one of your tenants.

| Field         | Description                                                                      |
| ------------- | -------------------------------------------------------------------------------- |
| Select a tenant | The tenant to read the policy from. Defaults to the tenant currently selected. |
| Select Policy | The Conditional Access policy in that tenant, listed by name. Required.          |

The policy is read live from the tenant, so the comparison always reflects its current configuration rather than what CIPP last deployed.

## Running the Comparison

Click **Compare** once both sources are filled in. The button is unavailable until each side has a valid selection, and while a comparison is running.

The result opens with a summary: a green banner when the two policies are identical, or an amber one giving the number of differences found. Both banners repeat the names of the two sources, with a tenant policy labelled by its tenant and a template marked as such.

## Reading the Differences

Where the policies differ, a table lists one row per setting:

| Column            | Description                                                                                                                                         |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Setting           | The setting that differs, written as its path in the policy, for example `conditions.users.includeGroups` or `grantControls.builtInControls`.      |
| Source A          | The value on the first side.                                                                                                                       |
| Source B          | The value on the second side.                                                                                                                      |
| Status            | **Different** when both sides set the value, or **Only in Source A** / **Only in Source B** when one side does not set it at all.                   |

Below the table, the full configuration of each side is shown as expandable JSON, so a difference can be read in context. Each side carries the label from the summary banner.

{% hint style="info" %}
Authentication strengths are compared by name only. A template stores just the strength's ID, while a live policy returns the strength fully expanded, so the extra detail on the live side is not reported as a difference.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

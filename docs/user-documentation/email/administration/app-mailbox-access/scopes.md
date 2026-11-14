# Management Scopes

This tab lists the Exchange management scopes in the tenant. A management scope selects mailboxes with a recipient filter, and an Exchange application role can be limited to the mailboxes in a scope. Scopes apply to the whole tenant, so one scope can be used by any number of role assignments, including those held by administrators rather than applications.

## Action Buttons

<details>

<summary>New Management Scope</summary>

Creates a management scope for the whole tenant, which can then be used for any role assignment. Shown only with the `Tenant.Application.ReadWrite` permission.

| Field            | Description                                                                                                     |
| ---------------- | --------------------------------------------------------------------------------------------------------------- |
| Name             | The name of the scope.                                                                                          |
| Recipient filter | An OPATH filter on mailbox properties, for example `Department -eq 'Sales'` or `CustomAttribute1 -eq 'Finance'`. |

</details>

## Table Details

| Column                 | Description                                                                                                            |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Name                   | The name of the scope.                                                                                                 |
| Recipient Filter       | The filter that decides which mailboxes are in the scope.                                                             |
| Scope Restriction Type | The kind of objects the scope applies to, as Exchange reports it.                                                     |
| Exclusive              | Whether the scope is exclusive. An exclusive scope does not restrict an application, so it is not offered when assigning an application role. |
| App Assignment Count   | How many Exchange application role assignments use the scope.                                                        |
| Other Assignment Count | How many other role assignments, such as those held by administrators, use the scope.                                 |
| When Created UTC       | When the scope was created.                                                                                           |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Delete Scope</td><td>Deletes the management scope. This cannot be undone. Shown only with the <code>Tenant.Application.ReadWrite</code> permission. Greyed out while any role assignment uses the scope: remove the assignments, or change their scope, first.</td><td>true</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}

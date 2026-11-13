# Application Roles

This tab lists every Exchange application role assignment in the tenant. An Exchange application role gives an application access to mailboxes through Exchange Online itself, in addition to any mailbox permission the application holds in Entra, and it does not show as a permission in Entra. Each assignment applies to every mailbox in the organisation, to the mailboxes in a management scope, or to the mailboxes in an administrative unit.

The delegating assignments Exchange gives the Organization Management role group for every application role by default are left out, because they grant no application any mailbox access.

## Action Buttons

<details>

<summary>Assign Role</summary>

Assigns one or more Exchange application roles to an enterprise application. Shown only with the `Tenant.Application.ReadWrite` permission.

| Field                         | Description                                                                                                                                                                       |
| ----------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enterprise application        | The application to assign the roles to, listed by display name and application ID.                                                                                              |
| Application roles             | One or more Exchange application roles. Roles in CIPP's risky set show their impact in the list.                                                                                  |
| Mailboxes the role applies to | **Every mailbox in the organization**, **A management scope** or **An administrative unit**. Defaults to every mailbox.                                                          |
| Management scope              | Shown when you choose a management scope. Pick one of the tenant's management scopes, listed with their recipient filters. Exclusive scopes do not restrict an application, so they are not listed. |
| Administrative unit           | Shown when you choose an administrative unit. Pick one of the tenant's administrative units.                                                                                     |

An application that is not yet registered in Exchange is registered first. A role the application already holds with the same scope is reported as already held rather than assigned twice. Role changes can take up to two hours to reach an application that is already in use.

</details>

## Table Details

| Column                       | Description                                                                                                                                                   |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| App Display Name             | The application that holds the role.                                                                                                                          |
| Role Assignee                | The holder of the assignment as Exchange names it.                                                                                                            |
| Role                         | The Exchange application role assigned.                                                                                                                       |
| Delegating                   | Whether the assignment is a delegating one. A delegating assignment grants no mailbox access itself, but lets its holder assign the role to applications.    |
| Impact                       | The impact rating of the role in CIPP's risky permissions set, where the role is in the set.                                                                 |
| Suspicion                    | The suspicion rating of the role in CIPP's risky permissions set, where the role is in the set.                                                              |
| Scope                        | Which mailboxes the assignment covers: **Organization**, **Management scope** or **Administrative unit**.                                                     |
| Scope Name                   | The management scope or administrative unit the assignment is limited to.                                                                                    |
| Custom Resource Scope Filter | The recipient filter of the management scope, for an assignment limited to one.                                                                              |
| Enabled                      | Whether the assignment is enabled.                                                                                                                            |
| When Created UTC             | When the assignment was created.                                                                                                                              |
| App Id                       | The application (client) ID of the application.                                                                                                               |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View app's Exchange access</td><td>Opens the <strong>Exchange</strong> tab of <a data-mention href="../../../tenant/administration/applications/enterprise-apps/spid.md">spid.md</a> for the application that holds the role. Greyed out for an assignment that does not belong to an application.</td><td>false</td></tr><tr><td>Change Scope</td><td>Assigns the role again with the scope you choose (every mailbox in the organisation, a management scope or an administrative unit), then removes the current assignment, so the application keeps access throughout. Shown only with the <code>Tenant.Application.ReadWrite</code> permission. Greyed out for an assignment that does not belong to an application.</td><td>true</td></tr><tr><td>Remove Role</td><td>Removes the role assignment from the application. The application loses this mailbox access within two hours. Shown only with the <code>Tenant.Application.ReadWrite</code> permission. Greyed out for an assignment that does not belong to an application.</td><td>true</td></tr></tbody></table>

{% hint style="info" %}
CIPP refuses to change the Exchange access of its own CIPP-SAM application.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

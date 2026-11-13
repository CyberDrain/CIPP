# Access Policies

This tab lists every application access policy in the tenant, once per policy. A policy limits which mailboxes the mailbox permissions an application holds in Entra can reach: **RestrictAccess** allows only the members of the named group, and **DenyAccess** every mailbox except theirs. Policies do not limit Exchange application roles.

Microsoft is replacing application access policies with Exchange application roles limited to a management scope or administrative unit, so new policies cannot be created in CIPP. Existing ones can be reviewed and removed here.

## Table Details

| Column          | Description                                                                                                                                     |
| --------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| App Names       | The applications the policy applies to. **Every app** for a policy that applies to all applications, and an application ID marked as not in this tenant where the application is not found. |
| Access Right    | **RestrictAccess** or **DenyAccess**.                                                                                                           |
| Scope Name      | The group whose members the policy allows or denies.                                                                                            |
| Is Valid        | Whether Exchange considers the policy valid. A policy can become invalid, for example when its group is deleted.                               |
| Description     | The description recorded on the policy.                                                                                                         |
| Policy Identity | The identity of the policy in Exchange.                                                                                                         |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View app's Exchange access</td><td>Opens the <strong>Exchange</strong> tab of <a data-mention href="../../../tenant/administration/applications/enterprise-apps/spid.md">spid.md</a> for the application the policy applies to. Greyed out for a policy that applies to every application or to more than one application in this tenant.</td><td>false</td></tr><tr><td>Remove Policy</td><td>Removes the policy. The mailbox permissions of the applications it names are no longer limited by it. Shown only with the <code>Tenant.Application.ReadWrite</code> permission.</td><td>true</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}

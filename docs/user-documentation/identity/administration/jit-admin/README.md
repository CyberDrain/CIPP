# JIT Admin

JIT Admin creates administrative accounts that expire on their own, so temporary elevation does not turn into a permanent standing privilege. Each account is created with a chosen set of roles and an expiry, and CIPP removes the roles or disables the account when the window closes. This page lists the accounts CIPP is tracking, whether they are currently active, and what they were created for.

JIT Admin is a tabbed page:

| Tab                 | What it is for                                                                                       |
| ------------------- | ---------------------------------------------------------------------------------------------------- |
| JIT Admins          | This list of JIT Admin accounts.                                                                     |
| Requests            | Requests waiting for approval, and the decisions made on earlier ones. See [requests.md](requests.md "mention"). |
| JIT Admin Templates | Saved settings for repeated grants. See [README.md](templates/README.md "mention").                  |
| JIT Role Templates  | Allow-lists of the roles a CIPP role can grant. See [README.md](role-templates/README.md "mention"). |

{% hint style="info" %}
When JIT Admin approval is switched on, a request that needs approval only appears on this list once it has been approved and created. Until then it is on the [requests.md](requests.md "mention") tab.
{% endhint %}

## Action Buttons

{% content-ref url="add.md" %}
[add.md](add.md)
{% endcontent-ref %}

## Filters

| Filter            | Shows                                                       |
| ----------------- | ----------------------------------------------------------- |
| Active JIT Admins | Accounts whose JIT elevation is currently in force.         |
| Expired/Disabled  | Accounts whose elevation has ended or has not been enabled. |

## Table Details

| Column               | Description                                                                                      |
| -------------------- | ------------------------------------------------------------------------------------------------ |
| User Principal Name  | The sign-in name of the account.                                                                 |
| Display Name         | The name of the account.                                                                         |
| Account Enabled      | Whether the account itself can sign in, separate from whether its elevation is active.           |
| Jit Admin Enabled    | Whether the JIT elevation is currently in force.                                                 |
| Jit Admin Start Date | When the elevation was scheduled to begin.                                                       |
| Jit Admin Expiration | When the elevation ends, at which point CIPP acts on the account.                                |
| Jit Admin Reason     | The reason recorded when the account was created, which is what makes the list reviewable later. |
| Jit Admin Created By | Who set the elevation up.                                                                        |
| Member Of            | The groups and directory roles the account currently belongs to.                                 |

{% hint style="info" %}
The JIT columns are not standard Entra ID properties. CIPP records them on the user account when it sets up the elevation, and uses them to know which accounts to act on at expiry. An account elevated outside CIPP does not appear here.
{% endhint %}

{% hint style="warning" %}
Under All Tenants, the first time the list is opened CIPP queues a background job to collect the data from every tenant and reports that it is still loading, so come back after a few minutes. Single-tenant views are always queried live.
{% endhint %}

{% hint style="info" %}
If your CIPP role has a [JIT Role Template](role-templates/README.md "mention") assigned, this list is filtered to JIT Admins whose roles fall entirely within that template. An account holding any role outside your allow-list is left off the list rather than shown with roles hidden.
{% endhint %}

## Table Actions

The row actions are the access and account controls from the [Users](../users/README.md) page that matter for a temporary admin account after it is created. Each is greyed out if your CIPP role lacks permission to edit users. **Create Temporary Access Pass** is pinned to the row, so a replacement pass can be issued without opening the menu.

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Create Temporary Access Pass</td><td>Issues a new Temporary Access Pass, for example when the one from creation has expired.</td><td>true</td></tr><tr><td>Re-require MFA registration</td><td>Clears the registered MFA methods so the account must register again.</td><td>true</td></tr><tr><td>Set Per-User MFA</td><td>Sets per-user MFA to <strong>Enforced</strong>, <strong>Enabled</strong>, or <strong>Disabled</strong>.</td><td>true</td></tr><tr><td>Set Sign In State</td><td>Enables or disables sign-in for the account.</td><td>true</td></tr><tr><td>Reset Password</td><td>Resets the account password.</td><td>true</td></tr><tr><td>Require Password Change at Next Logon</td><td>Forces a password change at the next sign-in without resetting the password.</td><td>true</td></tr><tr><td>Revoke all user sessions</td><td>Signs the account out of all sessions.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}

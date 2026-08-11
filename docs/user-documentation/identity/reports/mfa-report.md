# MFA Report

This report shows how every user in the tenant is protected by multifactor authentication, combining Entra's own registration report with per-user MFA state and Conditional Access coverage. It answers the question a single portal blade cannot: whether a given account would actually be challenged at sign-in, and by what.

{% hint style="info" %}
The registration and Conditional Access parts of this report need Microsoft Entra ID P1 or higher. Per-user MFA state is reported regardless, so an unlicensed tenant still produces a usable report with those columns empty.
{% endhint %}

## MFA Protection Criteria

A user is protected when at least one of the following applies. Reading the three together is the point of the report, because each covers a different set of sign-ins.

* **Per-User MFA** is set directly on the account, and challenges every sign-in regardless of conditions.
* **Covered by Security Defaults** protects the user through Microsoft's baseline settings, which enforce MFA when a sign-in is judged risky.
* **Covered by Conditional Access** protects the user through a policy, subject to whatever conditions that policy sets.

## Filters

| Filter                              | Shows                                                                              |
| ----------------------------------- | ---------------------------------------------------------------------------------- |
| Enabled, licensed users             | Active accounts holding a license, which is usually the population that matters.   |
| Enabled, licensed users missing MFA | The same population with no MFA methods registered. This is the list to work from. |
| No MFA methods registered           | Every account with nothing registered, including disabled and unlicensed ones.     |
| MFA methods registered              | Accounts with at least one method registered.                                      |
| Admin Users                         | Accounts holding a directory role.                                                 |

## Table Details

| Column           | Description                                                                                                                                           |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant           | The tenant the user belongs to. Shown when All Tenants is selected.                                                                                   |
| UPN              | The user's sign-in name.                                                                                                                              |
| Account Enabled  | Whether the account can sign in.                                                                                                                      |
| Is Licensed      | Whether the account holds a license.                                                                                                                  |
| MFA Registration | Whether Entra reports the user as having registered for MFA.                                                                                          |
| Per User         | The legacy per-user MFA state on the account: enforced, enabled or disabled.                                                                          |
| Covered By SD    | Whether Security Defaults are protecting the user.                                                                                                    |
| Covered By CA    | Whether a Conditional Access policy would enforce MFA, distinguishing a policy that covers all applications from one scoped to specific applications. |
| MFA Methods      | The authentication methods the user has registered.                                                                                                   |
| CA Policies      | The Conditional Access policies evaluated for this user, including whether they were included or excluded and how.                                    |
| Is Admin         | Whether the user holds a directory role.                                                                                                              |
| User Type        | Whether the account is a member or a guest.                                                                                                           |
| Cache Timestamp  | When the cached report was last refreshed.                                                                                                            |

{% hint style="warning" %}
**Covered By CA** reports that a policy targeting the user is enabled, not that the policy requires MFA under the conditions of a given sign-in. A policy scoped to specific applications leaves everything outside that scope unprotected, which is why the column distinguishes the two cases. Treat "Enforced - Specific Apps" as a prompt to check what the policy actually covers.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Set Per-User MFA</td><td>Sets the legacy per-user MFA state to Enforced, Enabled or Disabled, independently of any Conditional Access policy.</td><td>true</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}

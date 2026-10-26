---
description: Test a set of realistic sign-ins against a tenant's Conditional Access policies without anyone signing in.
---

# Sign-in Situations

This tab takes a set of realistic sign-ins and runs each one through Microsoft's Conditional Access What If API against the tenant's real policies. Nothing signs in and nothing changes: the API only reports what the policies would do. It is one of the three tabs of [README.md](README.md "mention"), and needs a single tenant selected.

{% hint style="warning" %}
The tenant needs an Entra ID P1 or P2 licence. Without one there are no Conditional Access policies to evaluate, and the tab shows a warning instead of results. The risk-based situations also need Entra ID P2; without it they are left out, and the summary line says how many.
{% endhint %}

## Sign in as

Every situation is evaluated as a real account from the tenant. CIPP picks one account for each group when the tab loads, and this card lets you change them. Changing any field re-evaluates straight away, and the fields reset to CIPP's own picks when you switch tenants.

| Field                 | Description                                                                                                                                                                                                                             |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Admin account         | The account used for the admin situations. Only enabled, non-guest accounts that hold a privileged directory role are offered. CIPP's own pick prefers an admin who is not excluded from any Conditional Access policy.             |
| Standard user account | The account used for the standard user situations. Guests and disabled accounts are left out. CIPP's own pick prefers a licensed account that holds no admin role and is not excluded from any Conditional Access policy.          |
| Guest account         | The account used for the guest situations.                                                                                                                                                                                              |
| Foreign country       | Where the "sign-in from a foreign country" situations come from. Defaults to Russia.                                                                                                                                                    |

## Situations

Situations are grouped by who is signing in: Admin accounts, Standard users, and Guests. Each row shows the result of the evaluation:

| Result                            | Meaning                                                                                  |
| --------------------------------- | ---------------------------------------------------------------------------------------- |
| Blocked                           | A policy blocks the sign-in.                                                             |
| Requires _controls_               | The policies demand controls, such as MFA or a compliant device, before letting it in.   |
| Allowed - _controls_ satisfied    | The sign-in gets in because it already meets what the policies ask for.                  |
| Allowed                           | No policy applies to the sign-in.                                                        |
| Not evaluated                     | The situation could not be run, and the row says why.                                    |

Each situation also has an expected result: most should be blocked, and some only need to be challenged for MFA or a compliant device. A protected row (green) shows the policies that stopped it. A row that gets through (red) explains which control is missing, and names any report-only policy that would have stopped it if it were enforced. Where the missing control matches a Conditional Access template, **Deploy a CA template** opens [list-template](../conditional/list-template/ "mention").

A situation shows Not evaluated when the tenant has no suitable account for that group, for example a tenant with no guest accounts, or when the evaluation itself fails.

The line above the list totals the sign-ins evaluated, how many are protected, how many get through (and how many of those only because a policy is report-only), how many could not be evaluated, and how many risk-based situations were left out for lack of Entra ID P2.

| Group          | Situations                                                                                                                                                                                                                                                               |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Admin accounts | Unmanaged device at a known location, sign-in from a foreign country, sign-in from a hosting-provider address, device-code flow, legacy authentication client, high sign-in risk, unmanaged macOS device, desktop client on an unmanaged device                            |
| Standard users | Unmanaged device in a browser, sign-in from a foreign country, device-code flow, legacy Exchange ActiveSync, other legacy client, high sign-in risk, high user risk, elevated insider risk, unmanaged Android device, unmanaged iOS device, desktop client on an unmanaged device |
| Guests         | Browser access at a known location, sign-in from a foreign country, legacy authentication client, unmanaged device in a browser, device-code flow, high sign-in risk, authentication transfer                                                                           |

The high sign-in risk, high user risk, and elevated insider risk situations are the risk-based ones that need Entra ID P2.

{% include "../../../../.gitbook/includes/feature-request.md" %}

---
description: Choose which containment actions run by default when a compromised user is contained.
---

# BEC Remediation Defaults

This page sets which [Business Email Compromise](../../identity/administration/bec/README.md) containment actions are switched on by default. The setting applies across the whole instance, for every tenant and every technician. It is reached from the **BEC Remediation Defaults** card on the General settings tab.

Each action is listed with its impact and a description of what it does. Switch on the actions you want as the default, then select **Save**. At least one action has to be on; **Save** stays greyed out until one is.

## Where the Defaults Apply

| Where                                                                                          | Effect                                                                                                                                                        |
| ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [Containment drawer](../../identity/administration/bec/case.md#containment) on a case          | The actions switched on here start selected. The technician can still change the selection for each case before running it.                                  |
| **Automatically contain users that newly appear at high risk** on the **NewRiskyUsers** alert  | Runs exactly the actions switched on here, with no one reviewing them first.                                                                                   |
| The `ExecBECRemediate` API called without a list of actions                                    | Runs the actions switched on here.                                                                                                                            |

The audit-log alert action **Execute a BEC Remediate** is not affected. It runs the actions chosen on the alert rule, or, when the rule chooses none, reset password, block sign-in, revoke sessions and disable inbox rules.

{% hint style="warning" %}
Automation confirms **Critical** actions without asking, because there is no one to type the user's UPN. Anything switched on here also runs unattended wherever the NewRiskyUsers auto-containment is enabled, so switch on tenant-wide actions such as **Disable transport rules** or **Disable rogue applications tenant-wide** only if you want them to run without anyone reviewing the case.
{% endhint %}

## Built-in Defaults

Until the defaults are saved here for the first time, these six actions are on:

| Action                         | Impact   |
| ------------------------------ | -------- |
| Reset password                 | Critical |
| Block sign-in                  | Critical |
| Revoke sessions                | High     |
| Remove MFA methods             | High     |
| Disable inbox rules            | High     |
| Block legacy mailbox protocols | High     |

Every other action starts switched off. The full list of actions and what each one does is under [Containment](../../identity/administration/bec/case.md#containment).

Changing the defaults requires the `CIPP.AppSettings.ReadWrite` permission. Every save is recorded in the logbook with the list of actions that were switched on.

{% include "../../../../.gitbook/includes/feature-request.md" %}

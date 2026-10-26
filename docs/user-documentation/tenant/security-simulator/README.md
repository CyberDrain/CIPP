---
description: >-
  See how real attacks would play out in a tenant today, and which controls
  close each gap.
---

# Security Simulations

{% hint style="warning" %}
Security Simulations is a beta feature controlled by the **Security Simulations** flag on the [features.md](../../cipp/settings/features.md "mention") tab of CIPP settings. It is on by default for installs that have no classic Standards templates, and off by default for installs that do. Behaviour and screens are still changing between releases.
{% endhint %}

Security Simulations shows you what an attacker would experience in a tenant right now. Instead of listing settings, it walks through the events that lead to a breach, checks each step against the tenant's real configuration, and tells you which control stops the attack, or which one is missing. Nothing on the page signs in as a user or changes the tenant by itself. The only changes happen when you pick a fix and confirm it.

### Overview

{% @storylane/embed subdomain="app" linkValue="hcjwbcxbcp71" url="https://app.storylane.io/share/hcjwbcxbcp71" %}

The page has three tabs, and each needs a single tenant selected:

| Tab                | Question it answers                                                   | Documented in                                            |
| ------------------ | --------------------------------------------------------------------- | -------------------------------------------------------- |
| Scenarios          | If this attack happened today, would it succeed?                      | This page                                                |
| Sign-in Situations | Would this kind of sign-in be blocked, challenged, or let through?    | [situations.md](situations.md "mention")                 |
| CA Gap Analysis    | What is wrong with the tenant's Conditional Access policies as a set? | [conditional-access.md](conditional-access.md "mention") |

## Scenarios

A scenario is an attack told as a sequence of steps. Each step is checked against the tenant in one of three ways:

* **Standards** are checked directly against the tenant, using the secure setting the scenario defines for each one. The setting a baseline chooses does not count as protection, so a baseline that weakens a standard does not make the step look safe. A standard that needs tenant-specific settings is judged from the tenant's baseline alignment instead, and reads **Needs configuration** until a baseline supplies them.
* **Alerts** are judged from the audit log alerts set up for the tenant in [alert-configuration](../administration/alert-configuration/ "mention"). An alert only counts as detecting an attack while the unified audit log is on for the tenant.
* **Sign-ins** are evaluated live through Microsoft's Conditional Access What If API, as an account from the tenant. Nothing actually signs in. An authentication strength counts as plain multifactor authentication unless every method it allows is phishing-resistant, so it does not stop attacks that need phishing-resistant authentication to block them.

The scenarios run alongside the nightly tests, so the list shows the last known result without you doing anything.

| Category                      | Scenarios                                                                                                                                                                                                                                                                                                                       |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Identity & Conditional Access | Global Admin on a non-compliant device, Device-code phishing, Guest account holding a directory role, Legacy authentication mailbox access, Malicious OAuth app consent, Password spray on an account without MFA, Privilege escalation by role assignment, Sign-in from outside allowed countries, Stolen session token replay |
| Audit & Detection             | Silent tenant: auditing turned off, Mass user deletion, MFA tampering after compromise                                                                                                                                                                                                                                          |
| Exchange & Email              | Mailbox rule exfiltration, Transport-rule exfiltration                                                                                                                                                                                                                                                                          |
| SharePoint & Data             | Anyone link on a sensitive site, Bulk sync to an unmanaged device, Guest re-share sprawl                                                                                                                                                                                                                                        |

## Scenario List

Scenarios are grouped by category. Scenarios that have never run sit under **Not checked yet**. Each row shows an outcome:

| Outcome                | Meaning                                                                                                             |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------- |
| Prevented              | A control in the tenant stops the attack.                                                                           |
| Detected               | No control can block the action, and an alert set up for the tenant fires when it happens.                          |
| Alerted, not prevented | The attack succeeds, but an alert set up for the tenant would fire.                                                 |
| Not prevented          | The attack succeeds and nothing detects it.                                                                         |
| Not licensed           | The tenant lacks a licence the scenario depends on.                                                                 |
| Could not be evaluated | The sign-in step could not be run, for example because the tenant has no suitable account or the evaluation failed. |
| Not checked yet        | The scenario has no result yet.                                                                                     |

Prevented, Alerted, and Not prevented rows also show how many gaps were found. The line above the list shows when the tenant was last checked and how many scenarios were prevented, not prevented, and not checked yet.

### Run all checks

Re-runs every scenario for the selected tenant, one at a time. The button counts through them as it goes. If any scenario fails to run, a warning says how many could not be checked once the run finishes.

## Scenario Detail

Click a scenario to open it. The top of the detail shows the account the sign-in step was evaluated as, when the scenario was last checked, and a verdict:

| Verdict                                      | Meaning                                                          |
| -------------------------------------------- | ---------------------------------------------------------------- |
| Blocked at "_step_"                          | The named step stops the attack.                                 |
| Detected: nothing can block this, and an alert fires when it happens | The action cannot be blocked by any control, and an alert detects it. |
| The attack succeeds, but an alert would fire | Nothing stops the attack, but an alert detects it.               |
| The attack succeeds, undetected              | Nothing stops or detects the attack.                             |
| The sign-in could not be evaluated           | The sign-in step could not be run, so the outcome is incomplete. |

Below the verdict is a timeline of the attack steps. Steps after the one that stops the attack are faded and marked not reached. Each step reports whether it is protected, partly protected, or unprotected, and lists the checks behind it:

* each standard involved, and whether it is in its secure state, or is drifted, not configured, an accepted deviation, or needs configuration
* each audit log operation, and whether an alert watches it
* for a sign-in step, any gap the sign-in exposed, and **Show the policies evaluated**, which lists every Conditional Access policy the evaluation considered and its result

{% hint style="warning" %}
If a sign-in is only stopped by a policy in report-only mode, the step says so. The policy would have blocked the sign-in had it been enforced, so it still counts as a gap until it is switched on.
{% endhint %}

### Today and With fixes

**Today** shows what happens in the tenant right now. **With fixes** replays the same timeline as if every control listed under What closes the gaps were in place, and shows which step would then stop the attack. Sign-in outcomes in this view are expected results, not a live evaluation. If no mapped control stops the attack even with every fix in place, the verdict says so.

### Run again

Re-checks just this scenario. A scenario that has never been checked runs by itself the first time you open it.

## What closes the gaps

The card beside the timeline lists every control that would close a gap. Each entry shows its type (Standard, Conditional Access policy, or Alert), the step it belongs to, and a button. When every mapped control is already in place, the card says so instead.

<details>

<summary>Add to baseline</summary>

Shown for a standard that is not in any baseline. Adds the standard to a baseline you already have, which applies it to its tenants on its next run. The baseline list is empty until a baseline exists; see [baselines](../baselines/ "mention").

| Field                                          | Description                                                                          |
| ---------------------------------------------- | ------------------------------------------------------------------------------------ |
| Baseline                                       | The baseline to add the standard to. Required.                                       |
| Stage                                          | The stage to add it to. Only shown when the baseline has more than one stage.        |
| Remediate automatically when the tenant drifts | Whether the baseline fixes the setting when the tenant drifts from it.               |
| Standard settings                              | The standard's own settings, the same ones it has when added to a baseline directly. |

</details>

<details>

<summary>Review</summary>

Shown for a standard that is already in a baseline but has drifted or is not applied. Opens [alignment.md](../baselines/alignment.md "mention") so you can see why.

</details>

<details>

<summary>Deploy</summary>

Shown for a Conditional Access policy. Opens [list-template](../conditional/list-template/ "mention"), where you deploy the template the fix names.

</details>

<details>

<summary>Enable</summary>

Shown for an alert. Creates an audit log alert for this tenant only. It then appears in [alert-configuration](../administration/alert-configuration/ "mention") like any other alert, where its conditions and actions can be changed.

| Field           | Description                                                                                                                                                               |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Actions to take | What happens when the alert fires: Execute a BEC Remediate, Disable the user in the log entry, Generate an email, Generate a PSA ticket, or Generate a webhook. Required. |
| Alert comment   | An optional note stored with the alert.                                                                                                                                   |

</details>

## Permissions

The Sign-in Situations and CA Gap Analysis tabs need the Security Simulations permission. The Scenarios tab reads the tenant's test results, so it also needs read access to reports, and **Run all checks** and **Run again** need write access to tests. Each fix button needs the permission of the area it changes: baselines for **Add to baseline**, and alerts for **Enable**.

{% include "../../../../.gitbook/includes/feature-request.md" %}

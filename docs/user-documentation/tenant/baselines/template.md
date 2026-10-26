---
description: Build a baseline, assign it to tenants and stage its rollout
---

# Add or Edit Baseline

The editor is where a baseline is given its name, its tenants, and the standards it applies. Standards are organised into stages, and a tenant receives a stage's standards only once it has met that stage's graduation conditions, which lets a baseline roll out gradually rather than all at once.

Leaving the page with unsaved work prompts you to confirm first.

## Page Actions

| Button            | Description                                                                                                                                                                                                                                                                                                                     |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Back to Baselines | Returns to [Manage Baselines](templates.md), even when the editor was opened from the Alignment page.                                                                                                                                                                                                                           |
| Save Baseline     | Saves the baseline once you confirm. Greyed out until the three items in **Setup Progress** are complete. After a save you are offered a check of the assigned tenants, which makes no changes and reports its results on the [Alignment](alignment.md) page. Otherwise the schedule picks the baseline up within twelve hours. |
| Add Stage         | Adds a stage, either empty or as a copy of the stage currently open, including its standards and graduation conditions. A baseline holds at most 20 stages; once it has 20 the button is greyed out and reads **Maximum of 20 stages reached**.                                                                                 |

## GitHub Sync

A baseline imported from a GitHub repository, or saved to one, shows a chip under the page title naming that repository. It reads **Synced from** the repository while the baseline matches the copy there, and **Modified since last push to** the repository once it holds changes the repository does not. Selecting the chip opens the baseline's file on GitHub. A copy opened with **Clone & Edit Baseline** carries no chip.

Saving a synced baseline adds these fields to the confirmation.

| Field          | Description                                                                                                                |
| -------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Save to GitHub | Pushes the baseline to the repository it came from as part of the save. Offered only when you can push to that repository. |
| Commit Message | The commit message for the push. Appears once **Save to GitHub** is on, and is then required.                              |

Saving without pushing keeps your changes in CIPP only, and the repository copy stays out of date until you push it. Where you cannot push to the repository, the next sync replaces your changes if the file changes upstream. To keep a copy that upstream never touches, use **Clone & Edit Baseline** on the [Manage Baselines](templates.md) page.

## Baseline Details

| Field                  | Description                                                                                                                                           |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Baseline Name          | The name the baseline is listed under. Required.                                                                                                      |
| Description            | Free text describing what the baseline is for.                                                                                                        |
| Assigned Tenants       | The tenants and tenant groups the baseline applies to. Required before the baseline can be saved.                                                     |
| Excluded Tenants       | Tenants and tenant groups that are left out even though a group or All Tenants assignment would otherwise include them. An excluded group leaves out every tenant in it. |
| Disable Scheduled Runs | Stops the baseline running on its schedule. It then runs only when you run it yourself, and deviations are neither detected nor corrected in between. |

## Alerting

| Field                                          | Description                                                                                                                            |
| ---------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Custom alert email addresses (comma separated) | Sends this baseline's alerts to these addresses instead of the global notification settings.                                           |
| Custom webhook URL                             | Sends this baseline's alerts to this webhook instead of the global notification settings.                                              |
| Disable Alerts for this baseline               | Stops all email, webhook, and PSA notifications for the baseline. Deviations are still detected and still shown on the Alignment page. |

Leave the address and webhook fields empty to deliver through the global CIPP notification settings. Which events raise an alert at all is set per standard, in the standard's own settings.

## Setup Progress

A checklist of the three things a baseline needs before it can be saved: a name, at least one tenant or tenant group, and at least one standard in any stage.

## Baseline Summary

| Field                       | Description                                                                              |
| --------------------------- | ---------------------------------------------------------------------------------------- |
| Stages                      | How many stages the baseline currently has.                                              |
| Standards across all stages | How many distinct standards it applies in total.                                         |
| Potential Secure Score gain | The Secure Score increase available if every standard in the baseline becomes compliant. |
| Last updated                | When the baseline was last saved, and by whom.                                           |

## Stages

Each stage has its own tab. Stage 1 always applies to every assigned tenant, so it carries no conditions. Every stage after it has graduation conditions deciding when a tenant moves up. Earlier stages keep applying, and where the same standard appears in two stages the later stage's settings win.

A chip next to the stage name shows how many tenants are currently sitting in that stage.

Stages after Stage 1 can be reordered with the up and down arrows beside the stage name. A stage keeps its name, standards and graduation conditions when it moves, and the stage numbers are renumbered to match. Stage 1 never moves and nothing can be moved above it, so the up arrow is greyed out on Stage 2 and the down arrow on the last stage.

### Graduation Conditions

Add as many conditions as you need. With more than one, a **Condition Logic** field appears and sets whether all of them must match or any one of them is enough. A stage with no conditions can only be advanced into by hand, from the Alignment page.

| Condition                                     | Description                                                                                                                        |
| --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Time in previous stage                        | The tenant has spent a given number of days or weeks in the stage before this one.                                                 |
| Tenant variable                               | A custom variable on the tenant matches the value you give, compared with equals, not equals, starts with, or does not start with. |
| Is in tenant group                            | The tenant belongs to the tenant group you choose.                                                                                 |
| All previous stage items applied successfully | Every standard from the earlier stages is compliant or accepted for the tenant. A standard the tenant is not licensed for does not hold the tenant back. |
| Manual approval by an operator                | The tenant waits until an operator advances it from the [Alignment](alignment.md) page.                                            |

### Standards In This Stage

**Add Standards** opens the catalogue, where standards can be searched by name, description, or benchmark tag, and narrowed by category, impact, the source that recommends them, and compliance tags. The results can be sorted, and shown as cards or as a list.

Each standard added to the stage expands to show its own settings, along with its impact, the Secure Score points it is worth, the benchmarks that recommend it, and the licences a tenant needs before it counts towards scoring. Standards that support it can be added more than once, so the same standard can be configured differently within one stage. Those standards carry a plus button on their row, with the tooltip **Add another** followed by the standard's name, which adds a further copy to the stage and opens it straight away so you can set it up.

Three settings are common to every standard.

| Setting                                        | Description                                                                                                                                                                                                                                                 |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Automatically fix this when the setting drifts | Corrects the setting back to its expected value on every run. Left off, the deviation is only reported.                                                                                                                                                     |
| Alert on new deviation                         | Raises an alert when the setting starts to deviate. No further alert is sent while it stays in **Drift**, however often the check runs. You are alerted again only after the setting is compliant or the deviation is accepted, and it then deviates again. |
| Alert when remediated                          | Raises an alert when automatic fixing corrects a setting that was not compliant. A setting that is reapplied on every run while already compliant raises no further alert.                                                                                                                                                                                             |

**Set all standards to** applies any one of those settings across every standard in the stage at once.

**Detect Intune Drift** and **Detect Conditional Access Drift** work differently from other standards. Instead of checking one setting, they raise a deviation for every Intune or Conditional Access policy in the tenant that no baseline template covers. They never change anything automatically, even with automatic fixing turned on. Review each policy on the [Alignment](alignment.md) page, where denying it removes the policy on the next run.

{% hint style="warning" %}
Each of these standards has a single result per tenant, however many policies it finds. You are alerted when the first uncovered policy appears. Any policy added or changed after that raises no alert of its own while the earlier ones are still awaiting a decision. To be alerted about new policies, accept every existing uncovered policy on the [Alignment](alignment.md) page, or add a template to the baseline that covers it, so the standard is back to compliant.
{% endhint %}

{% hint style="info" %}
Standards arrive with automatic fixing switched off. Nothing is changed in a tenant until you turn it on, either per standard or with **Set all standards to**.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

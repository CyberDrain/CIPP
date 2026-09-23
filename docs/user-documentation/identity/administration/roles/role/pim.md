# PIM Settings

The PIM tab shows how the role is held and the rules Privileged Identity Management applies to it, so a role can be judged on its configuration rather than only on who currently holds it. It opens from the [View Individual Role](README.md) header tabs and needs a single tenant selected.

Where the tenant is not PIM capable for this role, usually for want of an Entra ID P2 licence, a warning says so and the policy card is left off entirely. Assignments in that case are ordinary directory role memberships: there is no eligibility, no activation limit, and no policy to read.

Where the role's live settings are weaker than CIPP's secure floor, a warning lists each setting that falls short. The floor requires that activation expires within 24 hours and demands multi-factor authentication or an authentication context plus a justification, that eligible and active assignments expire within a year, and that creating an active assignment requires a justification. Entra's own defaults often sit below this.

## Assignment Breakdown

Three cards give the count for each way the role can be held. Selecting a card opens the matching assignments in a drawer, with the same columns and actions as the [Assignments](README.md#assignments) table on the Overview tab.

| Card                 | Description                                        |
| -------------------- | ---------------------------------------------------- |
| Permanent            | Active with no end date.                           |
| Eligible             | Can activate the role through PIM.                 |
| Active (time-bound)  | Active with an end date.                           |

## PIM policy

The role's current PIM settings, read from the tenant. The card header summarises the policy in a line, and a **PIM Templates** button opens the [templates](../templates/README.md) list. The settings are split into two groups.

**Activation**

| Setting                       | Description                                                                                                                |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Maximum activation duration   | How long an activation lasts before it expires.                                                                            |
| Activation requires           | Multi-factor authentication, an authentication context (named where one is set), or None.                                  |
| Justification on activation   | Whether the person activating must give a reason.                                                                          |
| Ticket on activation          | Whether a ticket number must be supplied.                                                                                  |
| Approval on activation        | Whether someone must approve the activation. Where approval is required and approvers are set, they are listed underneath. |

**Assignments**

| Setting                                        | Description                                                                                        |
| ---------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Maximum eligible assignment                    | How long an eligibility can run before it must be renewed.                                         |
| Maximum active assignment                      | How long an active assignment can run before it expires.                                           |
| Justification when creating active assignment  | Whether creating an active assignment requires a reason.                                           |
| MFA when creating active assignment            | Whether creating an active assignment requires multi-factor authentication.                        |
| Notification recipients                        | Who is notified about this role's PIM activity, where recipients are configured.                   |
| Meets secure floor                             | Whether the settings above satisfy CIPP's secure floor. The help icon beside it explains the floor. |

Durations are shown in whole units, so `P365D` reads as 1 year and `PT8H` as 8 hours. A setting with no limit reads as no expiration, meaning a permanent assignment is allowed.

## Role Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Create template from role settings</td><td>Builds a <a href="../templates/README.md">PIM template</a> from the role's current settings in this tenant, asking for a template name and an optional description. A live policy may sit below the secure floor; a template never stores that, so each offending value is raised to the closest value the floor allows and every raise is listed in the results. Greyed out without role write access, for a role that is not PIM capable, and where CIPP could not read the current policy.</td><td>false</td></tr></tbody></table>

{% include "../../../../../../.gitbook/includes/feature-request.md" %}

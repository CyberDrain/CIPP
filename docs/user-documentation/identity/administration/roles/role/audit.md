# Role Audit

The Audit tab lists the directory audit events Entra recorded against this role over the last 30 days, so a change in who holds a role can be traced back to who made it and when. It opens from the [View Individual Role](README.md) header tabs and needs a single tenant selected.

Events come from the tenant's own audit log, which Entra retains for a limited period, so an older change may have aged out even though it sits inside the 30 day window.

## Table Details

| Column          | Description                                                                              |
| --------------- | ------------------------------------------------------------------------------------------ |
| Date            | When the event was recorded, newest first.                                               |
| Activity        | What happened, as Entra names it, for example adding a member to a role.                 |
| Category        | The area of the directory the event belongs to.                                          |
| Result          | Whether the operation succeeded or failed.                                               |
| Initiated By    | The user principal name of whoever carried it out, where a user was responsible.         |
| Target Resources| What the event acted on, which for these events is the role and the principal involved.  |

Selecting a row opens the complete event as it was recorded, including the old and new values Entra captured, which is where the detail of a change lives when the summary columns are not specific enough.

{% include "../../../../../../.gitbook/includes/feature-request.md" %}

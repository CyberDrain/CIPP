# History

This timeline shows the actions CIPP has taken against the selected tenant, most recent first, covering the last five days by default. It is useful for working out why a policy did not apply, or confirming when a setting was enforced and by whom.

Only entries recorded against this tenant appear here. CIPP's own platform-level activity is not included.

## Timeline Entries

Each entry on the timeline carries the following.

| Element       | Description                                                                                                                         |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Date and time | When the action was recorded, shown to the left of the timeline in 24-hour time.                                                    |
| Severity      | A colored marker and chip naming the severity of the entry.                                                                        |
| API           | The CIPP function that recorded the entry, which is usually the quickest way to identify what was running.                          |
| IP            | The source address the action came from, where one was recorded.                                                                    |
| Message       | What happened. Messages longer than 256 characters are shortened, with **Show more** and **Show less** to expand and collapse them. |
| User          | The account that carried out the action, where one was recorded. Entries from scheduled or automated runs may not name a user.      |

## Severity Levels

Entries are returned for the severities below. Info, Warning and Error are color-coded on the timeline. Critical and Alert are shown with a neutral marker, with the severity itself named on the chip.

| Severity       | Description                                                          |
| -------------- | -------------------------------------------------------------------- |
| Info           | Normal activity, recorded for reference.                             |
| Warn / Warning | Something completed but not cleanly, or a condition worth attention. |
| Error          | The action failed.                                                   |
| Critical       | A failure treated as more serious than a standard error.             |
| Alert          | Raised by CIPP's alerting rather than by a direct action.            |

## Loading More History

**Load More** extends the range by a further seven days each time it is used, and the button names the total it will show next. The range always runs back from today, so extending it re-reads the whole period rather than paging further back.

{% hint style="info" %}
The Load More button appears below the timeline only once there is at least one entry to show. Where a tenant has had no activity in the last five days, the page reports that no logs were found and the range cannot be extended from here.
{% endhint %}

## Page Actions

| Action       | Description                                          |
| ------------ | ---------------------------------------------------- |
| Refresh Data | Re-reads the timeline for the range currently shown. |

{% include "../../../../.gitbook/includes/feature-request.md" %}

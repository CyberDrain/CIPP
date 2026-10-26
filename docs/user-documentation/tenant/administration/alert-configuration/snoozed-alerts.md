# Snoozed Alerts

Alert snoozes let you suppress a single noisy result from a scripted CIPP alert without disabling the alert itself. A snooze is scoped to one specific item in one tenant, so the rest of the alert keeps reporting as normal. This page lists everything currently snoozed so you can review it and lift a snooze early.

## Snoozing Alerts

Snoozes are set from the alert results, not from this page. There are two routes:

* **From an alert email** - Each result in the notification carries its own set of snooze buttons for 7, 14, 30 or 90 days. Clicking one opens CIPP and applies the snooze straight away, with no reason recorded, then offers a link back to this page.
* **From the dashboard** - The Alerts overview card has a snooze action per result, which opens a dialog with the options below and an optional free-text reason.

The dialog offers two kinds of snooze and one display choice:

* **For 7, 14, 30 or 90 days** - the item stops notifying until the date passes. If it is still being reported then, it notifies again. A timed snooze survives the item resolving in between, so a condition that clears and comes back inside the window stays quiet.
* **Until it resolves** - the item stops notifying for as long as the alert keeps reporting it. The snooze is removed automatically the first time the alert stops reporting it, so if the condition ever comes back it notifies again. Use this for "I know, I am dealing with it".
* **Keep it visible on the dashboard** - leaves the item in the dashboard's open list, marked as snoozed, instead of moving it to the snoozed section. Handy when you want the reminder without the noise.

There is deliberately no indefinite snooze. A snooze that never ends is how an alert gets missed.

{% hint style="info" %}
A snooze is matched on the content of the alert item, not just the user or object name. If the underlying detail changes, CIPP treats it as a new item and it will alert again even though a snooze exists for the earlier version.
{% endhint %}

A snoozed item is still tracked. It keeps its place on the [alert-history](alert-history.md "mention") page with the status `Snoozed`, and the alert keeps checking whether it is still true, so you can see whether the condition cleared while the snooze was in effect. Removing a snooze puts the item back to open straight away.

## Table Details

| Column         | Description                                                                                                                                                        |
| -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Alert          | The alert check the snooze applies to.                                                                                                                             |
| Tenant         | The tenant the snoozed item belongs to. A snooze never applies across tenants.                                                                                     |
| Item           | A short summary of the specific result that was snoozed, typically the user or object it relates to.                                                               |
| Snooze Reason  | The optional reason recorded when the snooze was set. Empty for snoozes applied from an alert email.                                                               |
| Snoozed By     | The CIPP user who set the snooze.                                                                                                                                  |
| Status         | `Active` while a timed snooze is in effect, `Until Resolved` for a snooze that lifts itself when the item resolves, and `Expired` once a timed snooze has run out. |
| Remaining Days | Whole days left before a timed snooze expires, rounded up. Shows `0` once expired, and for until-resolved snoozes.                                                 |
| Until Resolved | Whether the snooze lifts itself when the alert stops reporting the item.                                                                                           |
| Kept Visible   | Whether the item stays in the dashboard's open list, marked as snoozed, instead of being hidden.                                                                   |

{% hint style="info" %}
Expired snoozes stay listed until they are removed. They no longer suppress anything, so they are safe to leave in place, but clearing them keeps the list readable.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Remove Snooze</td><td>Removes the snooze after confirmation, so the alert fires again for that item on its next run.</td><td>true</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}

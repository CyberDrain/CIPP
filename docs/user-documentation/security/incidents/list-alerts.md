---
description: Review Microsoft 365 security alerts across your tenants.
---

# Alerts

Security alerts raised across the selected tenant's Microsoft 365 security products, listed newest first. Use it to see what has fired recently without moving between the individual security portals, and to move an alert on once you have dealt with it.

## Table Details

| Column           | Description                                                                                        |
| ---------------- | -------------------------------------------------------------------------------------------------- |
| Event Date Time  | When the earliest activity behind the alert took place. The table is sorted on this, newest first. |
| Status           | Where the alert sits in triage: `new`, `inProgress` or `resolved`.                                 |
| Title            | The alert's title, describing what was detected.                                                   |
| Severity         | The severity assigned to the alert by the product that raised it.                                  |
| Category         | The category the alert was raised under.                                                           |

The Extended Info flyout adds **Involved Users**, the user accounts recorded as evidence on the alert, so you can see who it concerns without opening the security portal.

{% hint style="info" %}
Selecting All Tenants queues a background job that collects alerts from every tenant, and the page tells you it is still loading. Come back in a few minutes for a complete list.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Set status to in progress</td><td>Marks the alert as being worked on.</td><td>true</td></tr><tr><td>Set status to resolved</td><td>Closes the alert.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}

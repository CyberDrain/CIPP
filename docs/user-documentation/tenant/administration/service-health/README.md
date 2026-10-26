# Service Health

Service Health brings Microsoft 365 service health and the Microsoft 365 message center into CIPP, so you can see which Microsoft services are having problems for a tenant, what Microsoft has said about them, and which announced changes need action, without signing in to the Microsoft 365 admin center.

The page is split into four tabs. This page covers the **Overview** tab, which is the one you land on.

| Tab            | Contents                                                                                                       |
| -------------- | -------------------------------------------------------------------------------------------------------------- |
| Overview       | A summary of service status, open issues, and message center posts, with the items that need attention first. |
| Status         | The current health of each Microsoft 365 service. See [status.md](status.md "mention").                        |
| Issues         | The incidents and advisories Microsoft has posted. See [issues.md](issues.md "mention").                       |
| Message Center | Microsoft's change notices and announcements. See [message-center.md](message-center.md "mention").            |

With All Tenants selected, every figure and list on the Overview covers the whole estate. An issue or message Microsoft posted to several tenants is listed once, with the tenants it reached shown against it.

{% hint style="info" %}
The Overview has no sync control of its own. Each of the other three tabs syncs its own data, so if a figure here is empty or out of date, sync it from the matching tab.
{% endhint %}

## Summary Bar

Four figures run across the top of the page. Selecting one opens the tab it summarises.

| Tile                 | Description                                                                                                                       |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| Services with issues | How many services are reporting any status other than operational. Opens the Status tab.                                          |
| Open incidents       | How many unresolved issues Microsoft has classified as incidents. Opens the Issues tab filtered to open incidents.                |
| Open advisories      | How many unresolved issues Microsoft has classified as advisories. Opens the Issues tab filtered to open advisories.              |
| Action required      | How many message center posts carry a date by which action is required. Opens the Message Center tab.                            |

## Service status

A donut chart of every service status check, split into **Operational**, **Degraded**, **Interrupted**, and **Other**, where Other covers any status Microsoft reports beyond those three. With All Tenants selected, each tenant's check for each service is counted separately. Selecting the card opens the Status tab.

## Open issues

A donut chart of unresolved issues, split into **Incidents** and **Advisories**. Selecting the card opens the Issues tab filtered to open issues.

## Message center

A donut chart of message center posts by category: **Plan for change**, **Stay informed**, and **Prevent or fix**. Selecting the card opens the Message Center tab.

## Open incidents and advisories

The eight most recently updated unresolved issues, newest first. Each one expands to show the affected service, whether it is an incident or an advisory, its current status, the tenant it applies to, when it was last updated, Microsoft's description of the impact, and the latest update Microsoft has posted.

### More info

Opens a flyout for the issue with its service, feature, classification, status, impact, and start and last updated times, followed by every update Microsoft has posted, newest first. The newest update is expanded; older ones expand when selected. With All Tenants selected, the flyout also lists every tenant the issue was posted to.

## Message center: action required

Up to eight message center posts that carry an action-required-by date, with the soonest deadline first. Each one expands to show the due date, category, affected services, tenant, and the full text of the post.

### More info

Opens a flyout for the post with its category, severity, services, tags, whether it is a major change, its action-required-by date, and when it was last updated, followed by the full text of the post. With All Tenants selected, the flyout also lists every tenant the post was sent to.

Links inside Microsoft's update and message text open in a new browser tab, so following one does not take you away from CIPP.

## Open issues by service

A bar chart counting unresolved issues per service, with the most affected service first. Selecting the card opens the Issues tab filtered to open issues.

## Services not operational

Every service reporting a status other than operational, in alphabetical order, with its current status and the tenant it applies to. When the same service has the same status in several tenants, it appears once with the number of tenants affected.

### More info

The information icon beside a service opens a flyout with the service, its status, the number of tenants reporting it, and the list of those tenants.

{% include "../../../../../.gitbook/includes/feature-request.md" %}

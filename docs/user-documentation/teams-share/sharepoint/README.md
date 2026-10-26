---
description: Review SharePoint sites and usage
---

# SharePoint

This page lists the SharePoint sites in the selected tenant, with the storage each one is consuming, the number of files it holds, and when it was last used. The list includes Teams channel sites, the separate sites Teams creates for private and shared channels, alongside the tenant's other sites. From here you can manage who has access to a site, change its sharing and storage settings, clean up old file versions, work through its recycle bin, and delete sites you no longer need.

{% hint style="warning" %}
The activity, file count and storage figures come from SharePoint's admin site data rather than from Microsoft's usage reporting, so they are not tied to a report Microsoft compiles on a schedule. In live mode the figures are current as of the request; in cached mode they are as current as the last sync. The **Report Refresh Date** column tells you when the figures on that row were read.

If activity, storage and file count are blank for every site, the site list itself is still complete, and CIPP shows a notice above the table: the usage merge failed, SharePoint admin access is partial, or the cache predates a successful sync. Sync the report, or switch to live data, and check SharePoint admin access for the tenant if the problem persists.
{% endhint %}

## Tenant Storage

A storage bar above the table shows how much of the tenant's overall SharePoint storage pool is in use, with the used, free and total figures alongside. These figures come from the tenant's quota in SharePoint rather than from usage reporting, so they are unaffected by report anonymisation. They reflect the quota as of CIPP's last collection of the tenant's data, and the bar does not follow the page's switch between live and cached data. The bar appears for a single tenant when you have SharePoint administration read access; if the quota cannot be read, it is replaced with a note that tenant storage usage is unavailable.

With All Tenants selected, the bar is replaced by a **Tenant Storage** table with one row per tenant, sorted with the fullest pool first. The columns are **Tenant**, **% of Quota**, **Storage Used In Gigabytes**, **Storage Free In Gigabytes**, **Storage Allocated In Gigabytes**, and **Geo Locations**.

## Action Buttons

{% content-ref url="add-site.md" %}
[add-site.md](add-site.md)
{% endcontent-ref %}

{% content-ref url="bulk-add-site.md" %}
[bulk-add-site.md](bulk-add-site.md)
{% endcontent-ref %}

## Table Details

| Column                        | Description                                                                              |
| ----------------------------- | ---------------------------------------------------------------------------------------- |
| Libraries                     | The site's top-level document libraries, reached through a **View libraries** button.    |
| Display Name                  | The name of the site.                                                                    |
| Created Date Time             | When the site was created.                                                               |
| Owner Principal Name          | The user recorded as the site's owner.                                                   |
| Last Activity Date            | The last date any activity was recorded on the site. Blank when there has been none.     |
| File Count                    | The number of files stored across the site.                                              |
| Storage Used In Gigabytes     | How much storage the site is using, rounded to two decimal places.                       |
| Storage Allocated In Gigabytes | The storage quota allocated to the site, rounded to two decimal places.                  |
| Report Refresh Date           | When CIPP read the usage figures on this row: the request time in live mode, or the last sync time in cached mode. |
| Web Url                       | The address of the site.                                                                 |

The Extended Info flyout also lists the site's members, showing each person's name, email address, the site group they belong to, whether they are a guest, and whether they are a site administrator.

## Libraries

The **Libraries** column opens a dialog listing the site's top-level document libraries, sorted by storage used.

| Column          | Description                                                                                                                                                             |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Display Name    | The library's name.                                                                                                                                                    |
| Site Type       | The kind of library, for example Document library or Site pages.                                                                                                       |
| File Count      | The number of files stored in the library.                                                                                                                             |
| Storage Used    | How much storage the library is using.                                                                                                                                 |
| Version size (est.) | An estimate of the storage taken up by old file versions, worked out by subtracting the library's current file and metadata size from its total size. Shown as a raw byte count rather than a formatted size. |
| % of Site       | The library's storage as a percentage of the site's total storage used.                                                                                                |
| Web Url         | The address of the library.                                                                                                                                            |

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Open library</td><td>Opens the library in SharePoint, in a new browser tab.</td><td>false</td></tr></tbody></table>

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Add Member</td><td>Adds one or more users to the site and puts them in the site role you choose: <strong>Members</strong>, <strong>Owners</strong> or <strong>Visitors</strong>. Each user is added separately, so one that cannot be added does not stop the rest, and the results list the outcome for each person. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Remove Member</td><td>Removes a user from one of the site's roles. The picker lists the site's current owners, members and visitors, so you can see which role each person holds before removing them. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Remove User From Site</td><td>Removes a user from the entire site at once, covering every site group and every direct permission grant they hold. Sharing links they have already received are not revoked by this. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Revoke Sharing Links</td><td>Revokes sharing links across the whole site in one go. You choose the scope: anonymous links only, anonymous links plus external user shares, or all sharing links including internal ones. This works from the sharing report data, so links created since the last sharing sync are not covered; run a sync from <a data-mention href="../reports/sharing-report.md">sharing-report.md</a> first for full coverage. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Edit Site</td><td>Opens the site's properties, prefilled with their current values, so you can change the site name, its external sharing capability, the default sharing link type and permission, any domain restrictions, anonymous link expiry, the lock state, storage limit and warning level, and the file version retention policy. Some settings are not editable on a site connected to a Microsoft 365 group. A site that is <strong>Read Only</strong> or <strong>No Access (site blocked)</strong> accepts a change to its lock state only: set the lock state to <strong>Unlocked</strong> and save, and any other changes you made at the same time are applied after the site unlocks. Other changes made while the site stays locked are skipped, and the result lists what was skipped. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Add Site Admin</td><td>Makes a user a site collection administrator, giving them full control of the site. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Remove Site Admin</td><td>Removes a user's site collection administrator rights. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Manage Permissions</td><td>Shows who has access to the site, or to one of its document libraries, and the permission level each user or group holds. From here you can grant a user or group a permission level, change or remove an existing assignment, stop a library inheriting the site's permissions so that it can hold its own, or restore inheritance. Viewing requires SharePoint site read access; making changes requires write access.</td><td>false</td></tr><tr><td>Check User Access</td><td>Answers whether a specific person can reach the site or one of its libraries, and by which routes. Group memberships are resolved, including nested groups, and each route is listed with what it grants. Because access can come from several routes at once, removing one does not necessarily remove access. Greyed out unless you have SharePoint site read access.</td><td>false</td></tr><tr><td>Delete Site</td><td>Deletes the selected site. Deleted sites can be restored from <a data-mention href="../deleted-sites.md">deleted-sites.md</a> for 93 days, after which they are permanently removed. For a site connected to a Microsoft 365 group, including any Teams site, the group's other resources are kept for only 30 days, so restoring after that returns the site but not the Team, its mailbox or its Planner. Greyed out unless you have SharePoint site write access, and always greyed out for sites SharePoint will not let you delete this way: the tenant admin site, the My Site host, search and compliance centres, the app catalogue, the root site, the content type hub, and Team channel sites, which are removed by deleting the channel in Teams.</td><td>true</td></tr><tr><td>Configure Version Cleanup…</td><td>Starts a background job that trims old file versions to reclaim storage. You choose the mode: <strong>Older than X days</strong> removes versions older than a set number of days, on a slider running from 30 to 365 days; <strong>More than X versions</strong> keeps only the newest major versions, with a second slider for how many of those majors keep their minor versions; and <strong>Sync policy</strong> trims existing version history to match the site's own version policy. Picking <strong>Sync policy</strong> against a single site shows that site's current policy first, so you can see what will be applied. The job only trims history, it never changes the policy itself. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Recycle Bin</td><td>Lists the items in the site's recycle bin, showing each item's name, location, type, state, size, who deleted it and when. Individual items can be restored from here. Greyed out unless you have SharePoint site recycle bin read access, and restoring requires recycle bin write access.</td><td>false</td></tr><tr><td>Check Cleanup Job Status</td><td>Shows the progress of the site's file version cleanup job, including how many lists, files and versions have been processed, how many versions were deleted, and how much storage was released. Tells you when no job has been run for the site. Greyed out unless you have SharePoint site read access.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

## Anonymised Reports

Microsoft 365 has a tenant-wide setting that conceals user names in usage reports, replacing them with hashes rather than user principal names. This only affects Microsoft's own usage reporting, not the SharePoint admin data this page reads, so it can only show up here in a cached report synced before CIPP moved to SharePoint admin data. Where CIPP detects that a cached report has come back anonymised, it shows a warning above the results.

The fix is on the tenant, not in CIPP: enabling the **Enable Usernames instead of pseudo anonymised names in reports** standard turns the setting off. For this page, syncing the report again or switching to live data resolves it straight away, since neither reads from the affected report.

{% include "../../../../.gitbook/includes/feature-request.md" %}

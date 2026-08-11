---
description: Review SharePoint sites and usage
---

# SharePoint

This page lists the SharePoint sites in the selected tenant, with the storage each one is consuming, the number of files it holds, and when it was last used. From here you can manage who has access to a site, change its sharing and storage settings, clean up old file versions, work through its recycle bin, and delete sites you no longer need.

{% hint style="warning" %}
The activity, file count and storage figures come from Microsoft's usage reporting, aggregated over a seven day window rather than showing the position at this moment. Microsoft refreshes that reporting once a day, so a change made today will not appear straight away. The **Report Refresh Date** column tells you how current the figures are.
{% endhint %}

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
| Display Name                  | The name of the site.                                                                    |
| Created Date Time             | When the site was created.                                                               |
| Owner Principal Name          | The user recorded as the site's owner.                                                   |
| Last Activity Date            | The last date any activity was recorded on the site. Blank when there has been none.     |
| File Count                    | The number of files stored across the site.                                              |
| Storage Used In Gigabytes     | How much storage the site is using, rounded to two decimal places.                       |
| Storage Allocated In Gigabytes | The storage quota allocated to the site, rounded to two decimal places.                  |
| Report Refresh Date           | The date Microsoft last refreshed the usage figures behind this report.                  |
| Web Url                       | The address of the site.                                                                 |

The Extended Info flyout also lists the site's members, showing each person's name, email address, the site group they belong to, whether they are a guest, and whether they are a site administrator.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Add Member</td><td>Adds a user to the site and puts them in the site role you choose: <strong>Members</strong>, <strong>Owners</strong> or <strong>Visitors</strong>. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Remove Member</td><td>Removes a user from one of the site's roles. The picker lists the site's current owners, members and visitors, so you can see which role each person holds before removing them. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Remove User From Site</td><td>Removes a user from the entire site at once, covering every site group and every direct permission grant they hold. Sharing links they have already received are not revoked by this. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Revoke Sharing Links</td><td>Revokes sharing links across the whole site in one go. You choose the scope: anonymous links only, anonymous links plus external user shares, or all sharing links including internal ones. This works from the sharing report data, so links created since the last sharing sync are not covered; run a sync from <a data-mention href="../sharing-report.md">sharing-report.md</a> first for full coverage. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Edit Site</td><td>Opens the site's properties, prefilled with their current values, so you can change the site name, its external sharing capability, the default sharing link type and permission, any domain restrictions, anonymous link expiry, the lock state, storage limit and warning level, and the file version retention policy. Some settings are not editable on a site connected to a Microsoft 365 group. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Add Site Admin</td><td>Makes a user a site collection administrator, giving them full control of the site. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Remove Site Admin</td><td>Removes a user's site collection administrator rights. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Manage Permissions</td><td>Shows who has access to the site, or to one of its document libraries, and the permission level each user or group holds. From here you can grant a user or group a permission level, change or remove an existing assignment, stop a library inheriting the site's permissions so that it can hold its own, or restore inheritance. Viewing requires SharePoint site read access; making changes requires write access.</td><td>false</td></tr><tr><td>Check User Access</td><td>Answers whether a specific person can reach the site or one of its libraries, and by which routes. Group memberships are resolved, including nested groups, and each route is listed with what it grants. Because access can come from several routes at once, removing one does not necessarily remove access. Greyed out unless you have SharePoint site read access.</td><td>false</td></tr><tr><td>Delete Site</td><td>Deletes the selected site. Deleted sites can be restored from <a data-mention href="../deleted-sites.md">deleted-sites.md</a> for 93 days, after which they are permanently removed. For a site connected to a Microsoft 365 group, including any Teams site, the group's other resources are kept for only 30 days, so restoring after that returns the site but not the Team, its mailbox or its Planner. Greyed out unless you have SharePoint site write access, and always greyed out for sites SharePoint will not let you delete this way: the tenant admin site, the My Site host, search and compliance centers, the app catalog, the root site, the content type hub, and Team channel sites, which are removed by deleting the channel in Teams.</td><td>true</td></tr><tr><td>Start Version Cleanup Job</td><td>Starts a background job that trims old file versions to reclaim storage. You choose the mode: <strong>Sync Policy</strong> applies the site's version policy to versions that already exist, <strong>Delete Older Than Days</strong> removes versions older than a set number of days (SharePoint requires at least 30), and <strong>Count Limits</strong> keeps a maximum number of major versions. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Recycle Bin</td><td>Lists the items in the site's recycle bin, showing each item's name, location, type, state, size, who deleted it and when. Individual items can be restored from here. Greyed out unless you have SharePoint site recycle bin read access, and restoring requires recycle bin write access.</td><td>false</td></tr><tr><td>Check Cleanup Job Status</td><td>Shows the progress of the site's file version cleanup job, including how many lists, files and versions have been processed, how many versions were deleted, and how much storage was released. Tells you when no job has been run for the site. Greyed out unless you have SharePoint site read access.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}

# Storage Report

The Storage Report shows where a single tenant's storage capacity is being used, across SharePoint sites, Teams-connected sites and OneDrive accounts, and highlights sites that are near quota, inactive, or holding storage that could be reclaimed. Teams storage is not a separate pool: a Teams-connected site is SharePoint capacity on a group or channel site, tracked alongside the rest of SharePoint. File-level M365 Archive usage is added to the report once SharePoint admin access is available and the data has been synced. The report requires a single tenant to be selected; under **AllTenants** the page shows a placeholder asking you to pick a tenant instead.

## Syncing Storage Data

The report reads from cached usage data rather than querying SharePoint and OneDrive live.

| Control      | Description                                                                                                                                                                     |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sync usage   | Queues a refresh of SharePoint site usage (including file-level archive metrics, where SharePoint admin access is available) and OneDrive usage for this tenant. This is what feeds the charts, the tables, and the near-quota and inactive views. Progress is shown next to it as **Usage sync**, and the report refreshes itself once the sync finishes. Greyed out unless you have SharePoint report write access. |
| Scan cleanup | Queues the cleanup scan described under [#finding-cleanup-opportunities](storage-report.md#finding-cleanup-opportunities "mention"). It fills the reclaim columns only, and does not refresh usage sizes. Unavailable until usage data has been synced, and reads **Rescan cleanup** once a scan has run. Greyed out unless you have SharePoint report write access. |
| Refresh      | Reloads the report from the cached data without running a new sync.                                                                                                                                                                                                    |

A **Last data refresh** line shows when the usage data and the cleanup scan were last refreshed, so you can tell how current the figures are before relying on them.

{% hint style="info" %}
If no cached data has been synced yet, or one of SharePoint or OneDrive comes back empty, a banner invites you to use **Sync usage**.
{% endhint %}

{% hint style="warning" %}
If SharePoint usage figures look empty even after a sync, Microsoft may not have generated a site usage report for the tenant yet. Sync again later, or check the reports in the SharePoint admin center directly.
{% endhint %}

## Anonymised Reports

Microsoft 365 has a tenant-wide setting that conceals user names in usage reports, replacing them with hashes rather than user principal names. Where CIPP detects that this report has come back anonymised, it shows a warning above the results.

The fix is on the tenant, not in CIPP. Enabling the **Enable Usernames instead of pseudo anonymised names in reports** standard turns the setting off, after which the report needs syncing again to pick up real names.

## Tenant Storage

A storage bar above the summary shows how much of the tenant's overall SharePoint storage pool is used, with chips for storage used, storage free and the total quota. On a tenant with more than one geo location, a chip is added for each geo showing its own usage. These figures reflect the quota as of CIPP's last collection of the tenant's data, and **Sync usage** does not refresh them. The bar needs SharePoint admin access; if it can't retrieve a quota figure for the tenant, it reads "Tenant storage usage is unavailable for this tenant" instead.

## Summary

A row of headline counts sits above the charts.

| Indicator                      | Description                                                                                                          |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| SharePoint Sites                | The number of SharePoint sites that are not connected to Teams.                                                        |
| Teams-Connected                 | The number of SharePoint sites connected to a Team (group or channel sites).                                           |
| OneDrive Accounts               | The number of OneDrive accounts.                                                                                       |
| Near quota (≥80%)               | Sites using 80% or more of their allocated storage.                                                                    |
| Inactive (≥90d)                 | Sites with no recorded activity in the last 90 days, or with no activity date at all.                                  |
| File-level archive (est.)       | Estimated storage held in file-level M365 Archive across all sites. Only shown once archive metrics have been synced. |
| Sites with file archive         | The number of sites that have any file-level archive usage. Shown alongside File-level archive (est.).                |
| Reclaimable (est.)              | Estimated storage a cleanup scan could reclaim across all scanned sites. Only shown after running **Scan cleanup**.    |

A row of chips beneath the summary repeats the near-quota, inactive, Teams-connected, top-site, file-archive and reclaimable highlights; clicking any of them switches to the SharePoint Sites tab.

## Charts

| Chart                                    | Shows                                                                                          |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------- |
| Storage by Workload (GB)                   | The share of storage used by SharePoint, Teams and OneDrive.                                      |
| Files by Workload                          | File counts across SharePoint, Teams and OneDrive.                                                |
| SharePoint by Site Template (GB)           | The top 8 site templates by storage used, across every SharePoint site regardless of workload.    |
| Largest SharePoint Sites (top 10)          | The 10 SharePoint sites using the most storage, excluding internal system sites such as the tenant admin site, search centres and the app catalogue. A **GB** / **%** toggle on the card switches the bars between gigabytes used and each site's share of the tenant's used storage. **%** is greyed out until a tenant storage figure is available. |

## Filters

Buttons above the SharePoint Sites table apply common filters in one click:

| Filter                    | Shows                                             |
| --------------------------- | ---------------------------------------------------- |
| Near quota (≥80%)           | Only sites using 80% or more of their allocated storage. |
| Has cleanup opportunity     | Only sites a cleanup scan has flagged as reclaimable. |
| Has file-level archive      | Only sites with file-level M365 Archive usage.        |
| Teams-connected             | Only sites connected to a Team.                       |
| SharePoint (non-Teams)      | Only sites not connected to a Team.                   |

## Finding Cleanup Opportunities

**Scan cleanup**, at the top of the page beside **Sync usage**, queues a scan of every SharePoint site in the tenant, aside from OneDrive personal sites and a handful of system sites such as the search centre, content type hub and app catalogue. Each site is checked for a large amount of old file versions, a full recycle bin, or a document library that has grown out of proportion to the rest of the site. The scan fills the reclaim columns only, so it is not a substitute for **Sync usage** and refreshes no storage sizes. Progress is shown next to **Cleanup scan**, the page switches to the SharePoint Sites tab, and the table refreshes itself once the scan finishes.

{% hint style="info" %}
If no cleanup scan has been cached yet, a banner invites you to use **Scan cleanup**.
{% endhint %}

Once a scan has run, sites with an opportunity show a **Cleanup** value and an estimated reclaim amount in the table, and the summary and chip row above pick up a **Reclaimable (est.)** figure. The table stays sorted by storage used, so sort on **Reclaim (est.)** to bring the largest opportunities to the top. Running **Scan cleanup** (now **Rescan cleanup**) again re-scans every site afresh.

Selecting **Cleanup…** on a site, or on a flagged row from the chip row, opens the storage cleanup drawer for that site:

* A composition breakdown, estimating how the site's storage divides between current files, previous file versions, and the recycle bin.
* A **Versions** tab listing the top libraries by estimated version storage, with a **Configure version cleanup…** button, and the status of any job already running or completed for the site.
* A **Recycle** tab summarising the first-stage and second-stage recycle bin, with a button to empty it entirely.

{% hint style="info" %}
The composition and version figures are estimates, not exact counts, and carry no file names. Reclaimed storage from a version cleanup job may differ from the estimate until the job itself reports how much was released.
{% endhint %}

Starting a version cleanup job asks for a mode. **Older than X days** removes versions older than a set number of days, on a slider running from 30 to 365 days. **More than X versions** keeps only the newest major versions, with a second slider for how many of those majors keep their minor versions. **Sync policy** trims existing version history to match the site's own version policy, and shows you that policy first so you can see what will be applied. A cleanup job only trims history, it never changes the policy itself: use **Edit Site**, or the SharePoint version control standard, for that. The **Versions** tab needs SharePoint site write access.

{% hint style="danger" %}
Emptying a recycle bin is permanent and cannot be undone. You choose whether to empty the first stage, the second stage, or both.
{% endhint %}

The **Recycle** tab needs SharePoint site recycle bin read access to view, and recycle bin write access to empty it.

## Table Details

The report is split into two tabs, **SharePoint Sites** and **OneDrive**, each counted in its own tab label.

### SharePoint Sites

| Column                        | Description                                                                                                             |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Libraries                        | The site's top-level document libraries, reached through a **View libraries** button. See [#libraries](storage-report.md#libraries "mention"). |
| Display Name                     | The name of the site.                                                                                                   |
| Workload                         | Whether the site is counted as Teams or SharePoint.                                                                     |
| Cleanup                          | The cleanup signals found for the site, such as old versions or a large recycle bin. Only shown after a cleanup scan.   |
| Reclaim (est.)                   | The estimated storage a cleanup would reclaim for the site. Only shown after a cleanup scan.                            |
| Archived File Disk Used Gigabytes | The site's file-level M365 Archive usage. Only shown once archive metrics have been synced.                             |
| File Archive Percent Of Site      | Archive usage as a percentage of the site's total storage used. Only shown once archive metrics have been synced.       |
| Allow File Archive               | Whether file-level archiving is allowed on the site. Only shown once archive metrics have been synced.                  |
| Root Web Template                | The site's underlying template, for example Group, Team Channel or Communication Site.                                 |
| Storage Used In Gigabytes        | How much storage the site is using, rounded to two decimal places.                                                      |
| Storage Allocated In Gigabytes   | The storage quota allocated to the site, rounded to two decimal places.                                                 |
| % of Quota                       | Storage used as a percentage of the site's allocated storage.                                                           |
| % of Tenant                      | Storage used as a percentage of the tenant's overall used storage.                                                      |
| File Count                       | The number of files stored across the site.                                                                             |
| Last Activity Date               | The last date any activity was recorded on the site. Treated as inactive when blank.                                    |
| Owner Principal Name             | The user recorded as the site's owner.                                                                                  |
| Web Url                          | The address of the site.                                                                                                |
| Report Refresh Date              | When the usage figures on this row were last synced.                                                                    |

#### Libraries

The **Libraries** column opens a dialog listing the site's top-level document libraries, sorted by storage used.

| Column          | Description                                                                                       |
| ------------------ | --------------------------------------------------------------------------------------------------- |
| Display Name       | The library's name.                                                                                 |
| Site Type          | The kind of library, for example Document Library or Site Pages.                                    |
| File Count         | The number of files stored in the library.                                                          |
| Storage Used In Bytes | How much storage the library is using.                                                           |
| Version size (est.) | An estimate of the storage taken up by old file versions in the library.                          |
| % of Site          | The library's storage as a percentage of the site's total storage used.                             |
| Web Url            | The address of the library.                                                                         |

### OneDrive

| Column                         | Description                                                          |
| --------------------------------- | ------------------------------------------------------------------------ |
| Display Name                      | The name on the OneDrive account.                                        |
| Owner Principal Name              | The user the OneDrive account belongs to.                                |
| Storage Used In Gigabytes         | How much storage the account is using, rounded to two decimal places.    |
| Storage Allocated In Gigabytes    | The storage quota allocated to the account, rounded to two decimal places. |
| % of Quota                        | Storage used as a percentage of the account's allocated storage.         |
| % of Tenant                       | Storage used as a percentage of the tenant's overall used storage.       |
| File Count                        | The number of files stored in the account.                               |
| Last Activity Date                | The last date any activity was recorded on the account. Treated as inactive when blank. |
| Web Url                           | The address of the OneDrive account.                                     |
| Report Refresh Date               | When the usage figures on this row were last synced.                     |

## Table Actions

### SharePoint Sites

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Cleanup…</td><td>Opens the storage cleanup drawer for the site (see Finding Cleanup Opportunities above). Greyed out for system sites and unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Set quota…</td><td>Sets the site's storage limit and warning level, in MB, prefilled from the site's current allocation where CIPP has a figure for it. Only takes effect when the tenant uses manual site storage limits. Greyed out for system sites and unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Open in SharePoint</td><td>Opens the site in a new browser tab.</td><td>false</td></tr><tr><td>Open Storage Metrics</td><td>Opens the site's classic Storage Metrics page in SharePoint admin, in a new browser tab.</td><td>false</td></tr><tr><td>Open in site browser</td><td>Opens the site in CIPP's site browser.</td><td>false</td></tr></tbody></table>

### OneDrive

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Set quota…</td><td>Sets the account's storage limit and warning level, in MB, prefilled from its current allocation where CIPP has a figure for it. Only takes effect when the tenant uses manual site storage limits. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Open in OneDrive</td><td>Opens the account in a new browser tab.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}

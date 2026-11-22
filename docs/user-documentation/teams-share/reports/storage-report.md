# Storage Report

The Storage Report shows where a single tenant's storage capacity is being used, across SharePoint sites, Teams-connected sites and OneDrive accounts, and highlights sites that are near quota, inactive, or holding storage that could be reclaimed. Teams storage is not a separate pool: a Teams-connected site is SharePoint capacity on a group or channel site, tracked alongside the rest of SharePoint. File-level M365 Archive usage is added to the report once SharePoint admin access is available and the data has been synced. The report requires a single tenant to be selected; under **AllTenants** the page shows a placeholder asking you to pick a tenant instead. The report can be exported as a PDF.

## Syncing Storage Data

The report reads from cached usage data rather than querying SharePoint and OneDrive live.

| Control      | Description                                                                                                                                                                     |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sync usage   | Queues a refresh of SharePoint site usage (including file-level archive metrics, where SharePoint admin access is available) and OneDrive usage for this tenant. This is what feeds the charts, the tables, and the near-quota and inactive views. Progress is shown next to it as **Usage sync**, and the report refreshes itself once the sync finishes. Greyed out unless you have SharePoint report write access; hovering over it shows the permission you need. |
| Scan cleanup | Queues the cleanup scan described under [#finding-cleanup-opportunities](storage-report.md#finding-cleanup-opportunities "mention"). It fills the reclaim columns only, and does not refresh usage sizes. Unavailable until usage data has been synced, and reads **Rescan cleanup** once a scan has run. Greyed out unless you have SharePoint report write access; hovering over it shows the permission you need. |
| **Scan large files** | Queues the large file scan described under [#large-files](storage-report.md#large-files "mention"). It keeps up to 25 of the largest files found in each site holding 1 GB or more and stores their names, locations and sizes for the **Large files** tab and the exported report. A site that could not be read keeps its results from the previous scan. It needs the usage sync to have run first. While the first scan is running, the **Large files** tab says so. If a scan for the tenant is already running, no second scan starts. Greyed out unless you have SharePoint report write access; hovering over it shows the permission you need. |
| **Refresh**  | Reloads everything on the page from the cached data, including the **Large files** tab and the Microsoft 365 Archive banner, without running a new sync or scan. |
| **Export Report** | Opens a preview of the report as a PDF in your report branding, covering SharePoint and OneDrive storage use, version history and version policies per library, recycle bins, and inactive sites. When the last large file scan found files, it adds an **Archive Opportunities** page listing the largest files, the archive candidates, what archiving them would cost at Microsoft's US list prices, the total storage currently archived at file level, and the wait to get an archived file back. Each table on that page lists at most 15 files. When no file qualifies for archiving, the page leaves out the candidates table and the cost, and says that no eligible active files last changed more than 12 months ago were found. Where the scan could not search every folder, the page says the list is the largest files found. You can then download it. The PDF is built from the last usage sync, cleanup scan and large file scan. Greyed out until usage data has been synced.

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

**Scan cleanup**, at the top of the page beside **Sync usage**, queues a scan of every SharePoint site in the tenant, aside from OneDrive personal sites and a handful of system sites such as the search centre, content type hub and app catalogue. Each document library's version policy is recorded, and each site is checked for a large amount of old file versions, a full recycle bin, or a document library that has grown out of proportion to the rest of the site. The scan fills the reclaim columns only, so it is not a substitute for **Sync usage** and refreshes no storage sizes. Progress is shown next to **Cleanup scan**, the page switches to the SharePoint Sites tab, and the table refreshes itself once the scan finishes.

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

## Microsoft 365 Archive

Where SharePoint admin access is available, a banner above the report says whether the tenant is ready to archive content.

| Banner                                                | Meaning                                                                                                                                                                                                 |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Microsoft 365 Archive is turned on**                    | Files and sites can be archived. The banner gives the total storage currently archived at file level. It adds how many sites do not allow file archiving only when at least one site (other than system sites) has it switched off, and adds that new sites do not allow file archiving by default only when that is the tenant's default. |
| **File archiving is switched off for this tenant**        | Whole sites can still be archived, but users cannot archive individual files. The **Set SharePoint file archiving (Microsoft 365 Archive)** baseline turns it back on.                                  |
| **Microsoft 365 Archive does not appear to be turned on** | Nothing can be archived until Microsoft 365 Archive is turned on for the tenant in the Microsoft 365 admin center, which needs pay-as-you-go billing through an Azure subscription.                      |
| **This tenant's SharePoint settings have not been collected yet** | CIPP has not stored the tenant's SharePoint settings yet, so it cannot say whether Microsoft 365 Archive is turned on. They are collected with the nightly tenant data, and the banner says what to do. |
| **This tenant's SharePoint settings could not be read**   | CIPP could not read the stored SharePoint settings. The banner gives the reason; reload the page to try again.                                                                                          |

The banner reflects the tenant's SharePoint configuration as of CIPP's last collection of the tenant's data, so a change made in the Microsoft 365 admin center shows up after the next collection.

{% hint style="warning" %}
Archived content is not available straight away. Bringing a file or site back is instant for the first 7 days after it was archived. After that it can take up to 24 hours, and nobody can open it until that finishes. Agree this with the customer before archiving anything they might need at short notice.
{% endhint %}

{% hint style="info" %}
Microsoft only charges for archived storage once the tenant's active and archived storage together exceed its SharePoint storage quota, so archiving content in a tenant that is at its limit frees space without a charge. See Microsoft's [pricing model for Microsoft 365 Archive](https://learn.microsoft.com/en-us/microsoft-365/archive/archive-pricing).
{% endhint %}

## Finding Large Folders and Files

**View contents**, on a document library in the **Libraries** dialog or on the **Libraries** tab, opens that library's folders and files with their sizes, so you can name exactly what is using a site's storage before discussing it with the customer. Site Pages libraries have no **View contents** button.

| View              | Description                                                                                                                                                                                                                                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Folders and files** | Lists the folders and files in the current folder, largest first. Select a folder to open it. The path above the table shows where you are, and selecting any part of it takes you back up.                                                                                                          |
| **Largest files**     | Lists up to 50 of the largest files found in the current folder and the folders below it. Where the folder is too large to search in one go, up to 20 of the folders that were not opened and could still hold a larger file are listed with the files, and selecting one searches inside it. Any other folders that were not opened are not listed. |

| Column                  | Description                                                                                                                            |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| Name                    | The name of the folder or file.                                                                                                        |
| Type                    | Whether the row is a folder or a file.                                                                                                 |
| Folder Path             | The folder the file sits in, from the top of the library. Shown in the **Largest files** view.                                         |
| Size                    | The current size of the file, or of everything inside the folder. These can add up to less than the library's **Storage Used**, which also counts version history. |
| % of Library            | The size as a percentage of the library's storage used.                                                                                |
| Item Count              | The number of files and folders directly inside a folder. Blank for files.                                                             |
| **Archive Status**      | Whether a file is **Active**, **Archived**, or **Reactivating** in Microsoft 365 Archive, or **Unknown** where Microsoft gave a status CIPP does not recognise. Blank for folders. |
| Last Modified Date Time | When the folder or file was last changed.                                                                                              |
| Last Modified By        | Who last changed the folder or file.                                                                                                   |

### Archiving Files and Folders

Files that are large but rarely opened can be moved to Microsoft 365 Archive from the same dialog, which frees SharePoint storage without deleting anything. An archived file stays listed in its library, but nobody can open it until it is reactivated.

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td><strong>Open folder</strong></td><td>Opens the folder. Greyed out for files.</td><td>false</td></tr><tr><td><strong>Archive</strong></td><td>Moves the file, or the eligible files in the folder, to Microsoft 365 Archive. A folder is archived in the background by Microsoft 365, so a large folder takes a while to finish. Greyed out for files that are not <strong>Active</strong>, for content Microsoft 365 Archive cannot archive (see below), and unless you have SharePoint site write access.</td><td>true</td></tr><tr><td><strong>Reactivate</strong></td><td>Brings an archived file, or every archived file in the folder, back into SharePoint storage. Files archived in the last 7 days come back straight away, and older files can take up to 24 hours. Greyed out for files that are not <strong>Archived</strong>, and unless you have SharePoint site write access.</td><td>true</td></tr><tr><td><strong>Open in SharePoint</strong></td><td>Opens the folder or file in a new browser tab.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
Archiving a file only works where the tenant is ready for it (see [#microsoft-365-archive](storage-report.md#microsoft-365-archive "mention")) and the site allows file archiving (the **Allow File Archive** column).
{% endhint %}

Microsoft 365 Archive cannot archive OneNote files (`.one` and `.onetoc2`), SharePoint pages (`.aspx`), or anything in a site's **Site Assets** library, so **Archive** is greyed out for them, and archiving a folder leaves them active. A folder that is only named SiteAssets inside another library can be archived. For a file that is **Reactivating** or **Unknown**, both **Archive** and **Reactivate** are greyed out.

{% hint style="warning" %}
A reactivated file cannot be archived again for 120 days.
{% endhint %}

## Table Details

The report is split into four tabs, **SharePoint Sites**, **OneDrive**, **Libraries** and **Large files**, each counted in its own tab label.

### SharePoint Sites

| Column                        | Description                                                                                                             |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Libraries                        | The site's top-level document libraries, reached through a **View libraries** button. See [#libraries](storage-report.md#libraries "mention"). |
| Display Name                     | The name of the site.                                                                                                   |
| Workload                         | Whether the site is counted as Teams or SharePoint.                                                                     |
| Archive Status                   | Whether the whole site is **Active**, **Archived** or **Reactivating** in Microsoft 365 Archive, or **Unknown** where Microsoft gave a status CIPP does not recognise. Only shown after a **Sync usage** that collected it. |
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

The **Libraries** column opens a dialog listing the site's top-level document libraries, sorted by storage used. A document library's **View contents** button opens its folders and files (see [#finding-large-folders-and-files](storage-report.md#finding-large-folders-and-files "mention")).

| Column          | Description                                                                                       |
| ------------------ | --------------------------------------------------------------------------------------------------- |
| **Contents**       | A **View contents** button that opens the library's folders and files, largest first. Blank for Site Pages libraries. |
| Display Name       | The library's name.                                                                                 |
| Site Type          | The kind of library, for example Document Library or Site Pages.                                    |
| File Count         | The number of files stored in the library.                                                          |
| Storage Used       | How much storage the library is using.                                                           |
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

### Libraries

The **Libraries** tab lists every document library found by the cleanup scan, across all scanned sites, sorted by estimated version storage so the libraries holding the most old versions come first. It stays empty until you run **Scan cleanup**.

| Column             | Description                                                                                                                             |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| **Contents**       | A **View contents** button that opens the library's folders and files, largest first. Blank for Site Pages libraries.                  |
| Site               | The site the library belongs to.                                                                                                        |
| Display Name       | The library's name.                                                                                                                     |
| Storage Used       | How much storage the library is using in total.                                                                                      |
| Current Files      | The storage taken up by the current version of each file, without version history.                                                     |
| Version size (est.) | An estimate of the storage taken up by old file versions in the library.                                                               |
| Versions %         | Estimated version storage as a percentage of the library's total storage.                                                              |
| Version Policy     | The library's version history policy: **Versioning off**, **Automatic**, a version limit with versions that never expire, or a version limit with versions that expire after a set number of days. |
| File Count         | The number of files stored in the library.                                                                                              |
| Web Url            | The address of the library.                                                                                                             |

### Large files

The **Large files** tab lists the largest files across the tenant from the last large file scan, sorted by size. It stays empty until you run **Scan large files**. The scan keeps up to 25 of the largest files found in each site holding 1 GB or more. A site that could not be read keeps its results from the previous scan. The sizes and archive status shown are as they were when the scan ran, so scan again after archiving.

After you start a scan, a note above the table tells you when something needs your attention. A scan run over earlier results shows no note while it runs, or when it finishes and stores new files.

| Message | Meaning |
| ------- | ------- |
| **The large file scan has started** | Shown while the first scan for the tenant is running. Its progress shows next to **Scan large files**, and the files appear when it finishes. |
| **A large file scan for this tenant was already running when you asked** | A scan was already running, so a second one was not started. Use **Refresh** to check for its results. The note goes once the table lists files from that scan. |
| **The large file scan did not store new results** | The scan ended, but none of the files listed was collected by it, so they are from the previous scan. Check the logbook for the reason, then scan again. |
| **Some sites could not be read by the large file scan** | The scan stored new files but hit errors on some sites, whose files may be missing or from the previous scan. Check the logbook for the detail. |
| **The large file scan did not finish** | The scan ended without storing any results. Check the logbook for the reason, then scan again. |
| **The large file scan finished and no large files were stored** | The scan ran but found nothing to store. Only sites holding 1 GB or more are scanned, so a tenant with smaller sites has no large files to list. If you expected files, the logbook has the detail. |

If the list itself cannot be read, an error is shown above the table as well as any of these notes.

When the files listed for a site come from a search that did not finish, because the site holds more folders than the scan reads, a note above the table says not every folder was searched. The list is then the largest files found, and a larger file may still be in a folder the scan did not reach: use **View folders and files** on that library to look inside it. Sites whose search finished get no note.

When the scan found files, a **What archiving would save** card above the table counts the archive candidates (files that are **Active**, can be archived, and have not changed in 12 months), the SharePoint storage that archiving them would free, and the monthly cost of archiving them against buying the same space as extra SharePoint storage. The card is not shown when the scan found no files. Where no file qualifies, the card says that no eligible active files last changed more than 12 months ago were found. The two prices default to Microsoft's US list prices per GB per month and can be changed to your own, and your prices are kept while you move between tabs. The archive cost is exact only when CIPP has the tenant's SharePoint storage figures, which needs SharePoint admin access. The estimate then uses the figures CIPP last collected for the tenant, not a live reading. Without them, the card gives the most archiving could cost.

| Column                  | Description                                                                                        |
| ----------------------- | -------------------------------------------------------------------------------------------------- |
| Name                    | The name of the file.                                                                              |
| Site                    | The site the file is in.                                                                           |
| Library Name            | The document library the file is in.                                                               |
| Folder Path             | The folder the file sits in, from the top of the library.                                          |
| Size                    | The size of the file.                                                                              |
| **Archive Status**      | Whether the file was **Active**, **Archived**, or **Reactivating** when the scan ran, or **Unknown** where Microsoft gave a status CIPP does not recognise. |
| **Archive Candidate**   | **Yes** for a file that is **Active**, can be archived, and has not changed in 12 months. OneNote files, SharePoint pages and files in **Site Assets** are never candidates. |
| Last Modified Date Time | When the file was last changed. This report uses this date to judge how long a file has gone unchanged. |
| Last Modified By        | Who last changed the file.                                                                         |

Two filter buttons above the table narrow it to **Archive candidates (not changed in 12 months)** or to files that are already **Archived**.

## Table Actions

### SharePoint Sites

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Cleanup…</td><td>Opens the storage cleanup drawer for the site (see Finding Cleanup Opportunities above). Greyed out for system sites and unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Set quota…</td><td>Sets the site's storage limit and warning level, in MB, prefilled from the site's current allocation where CIPP has a figure for it. Only takes effect when the tenant uses manual site storage limits. Greyed out for system sites and unless you have SharePoint site write access.</td><td>true</td></tr><tr><td><strong>File archiving…</strong></td><td>Sets whether users can archive files on the site with Microsoft 365 Archive. Turning it off only stops new files being archived: files that are already archived stay archived and can still be reactivated. The change applies straight away, but the switch, the <strong>Allow File Archive</strong> column and the banner show the old setting until the next <strong>Sync usage</strong>. Greyed out for system sites and unless you have SharePoint site write access.</td><td>true</td></tr><tr><td><strong>Archive site…</strong></td><td>Archives the whole site with Microsoft 365 Archive. Nobody can open the site or any file in it until it is reactivated, and it stops counting towards SharePoint storage. A hub site must be unregistered first, and the private and shared channel sites of a team are not archived with it. Runs on one site at a time, so each site is confirmed on its own. Greyed out for system sites, for sites that are <strong>Archived</strong> or <strong>Reactivating</strong> at the last <strong>Sync usage</strong>, and unless you have SharePoint site write access.</td><td>false</td></tr><tr><td><strong>Reactivate site…</strong></td><td>Brings an archived site back. A site archived in the last 7 days comes back straight away, and an older one can take up to 24 hours. Greyed out for system sites, for sites that are <strong>Active</strong> or <strong>Reactivating</strong> at the last <strong>Sync usage</strong>, and unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Open in SharePoint</td><td>Opens the site in a new browser tab.</td><td>false</td></tr><tr><td>Open Storage Metrics</td><td>Opens the site's classic Storage Metrics page in SharePoint admin, in a new browser tab.</td><td>false</td></tr><tr><td>Open in site browser</td><td>Opens the site in CIPP's site browser.</td><td>false</td></tr></tbody></table>

### Libraries

These actions are available on a library in the **Libraries** dialog and on the **Libraries** tab.

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td><strong>View folders and files</strong></td><td>Opens the library's folders and files, largest first (see Finding Large Folders and Files above). Greyed out for Site Pages libraries.</td><td>false</td></tr><tr><td><strong>Open library</strong></td><td>Opens the library in a new browser tab. Available in the <strong>Libraries</strong> dialog.</td><td>false</td></tr></tbody></table>

### Large files

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td><strong>Archive</strong></td><td>Moves the file to Microsoft 365 Archive. Greyed out for files that were not <strong>Active</strong> when the scan ran, for OneNote files, SharePoint pages and files in a site's <strong>Site Assets</strong> library, and unless you have SharePoint site write access.</td><td>true</td></tr><tr><td><strong>Reactivate</strong></td><td>Brings an archived file back into SharePoint storage. Files archived in the last 7 days come back straight away, and older files can take up to 24 hours. Greyed out for files that were not <strong>Archived</strong> when the scan ran, and unless you have SharePoint site write access.</td><td>true</td></tr><tr><td><strong>Open in SharePoint</strong></td><td>Opens the file in a new browser tab.</td><td>false</td></tr></tbody></table>

### OneDrive

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Set quota…</td><td>Sets the account's storage limit and warning level, in MB, prefilled from its current allocation where CIPP has a figure for it. Only takes effect when the tenant uses manual site storage limits. Greyed out unless you have SharePoint site write access.</td><td>true</td></tr><tr><td>Open in OneDrive</td><td>Opens the account in a new browser tab.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}

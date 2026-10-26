# Sharing Report

The SharePoint and OneDrive Sharing Report shows the sharing links and external shares across a single tenant's SharePoint sites and OneDrive accounts, drawing attention to the riskiest ones: anonymous links, anonymous links that allow editing or never expire, and shares reaching external recipients. It requires a single tenant to be selected and is not available for All Tenants. The data is compiled from cached scans that you trigger and keep current from this page, and the report can be exported as a PDF.

## Syncing Sharing Data

The report reads from cached scans rather than querying SharePoint and OneDrive live. The first time you open it for a tenant there is no data yet, and a prompt invites you to run a scan. The controls at the top of the page build and refresh that data.

| Control       | Description                                                                                                                                                                                                                                                                                 |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sync data     | Queues scans of the tenant's SharePoint sites and OneDrive accounts for sharing links, together with SharePoint and OneDrive usage data. Scanning every drive can take a while on large tenants, particularly the first time. Progress is shown next to the button, and the report refreshes itself once the scans finish. Greyed out unless you have SharePoint report write access. |
| Refresh       | The refresh icon reloads the report from the cached data without running a new scan. Use it when a scan has finished elsewhere, or when someone else has refreshed the cache.                                                                                                                |
| Export Report | Opens a preview of the report as a PDF, which you can then download. Greyed out until the report has data.                                                                                                                                                                                   |

The time of the last completed scan is shown as "Last data refresh."

Results are written as the scan works through the tenant, so the report fills in library by library rather than staying empty until every drive has been read. Refreshing part-way through shows what has been scanned so far, and the totals settle once the scan finishes.

The first scan of a tenant reads every drive in full. Later syncs collect only what has changed since the previous one, so they finish considerably faster, and a full rescan is run periodically to catch anything a change-only pass would miss. A scan interrupted before it finishes, by a timeout on a large tenant for example, picks up where it stopped rather than starting the tenant over, and a library too large to read in one pass resumes by itself until it is done.

Sites that could not be read keep the links an earlier scan found for them rather than dropping out of the report, so those rows may be out of date. The same applies to a library where Microsoft throttled the scan before every item could be read: its existing links are kept, and the library is read in full on the next sync.

Links belonging to sites or libraries that no longer exist in the tenant are removed once the scan finishes, as are the links on a locked site: a lock blocks all access to that site's content, sharing links included, so those links no longer work. Locked sites are most often former employees' OneDrive accounts, and their links reappear at the next sync after the lock is lifted. The Preservation Hold Library is not scanned, as it holds retained copies that cannot be shared.

## Summary

A row of headline counts sits above two cards that break the environment down further.

| Indicator               | Description                                                |
| ----------------------- | ---------------------------------------------------------- |
| Sharing Links           | The total number of sharing links found.                   |
| Anonymous Links         | Links that anyone can use without signing in.              |
| External Links & Shares | Links and shares given to people outside the organisation. |
| Internal Links          | Links usable only by people inside the organisation.       |

### Sharing Risk Highlights

| Indicator            | Description                                                          |
| -------------------- | -------------------------------------------------------------------- |
| Anonymous & Editable | Anonymous links that also allow editing.                             |
| Anonymous, No Expiry | Anonymous links with no expiry date set.                             |
| Shared Folders       | Shares placed on a folder, which carry down to everything inside it. |
| External Recipients  | The number of external recipients that items have been shared with.  |

### Environment

| Indicator             | Description                                    |
| --------------------- | ---------------------------------------------- |
| SharePoint Sites      | The number of SharePoint sites in the tenant.  |
| Teams-Connected Sites | SharePoint sites that are connected to a Team, including the separate sites of its private and shared channels. |
| OneDrive Accounts     | The number of OneDrive accounts.               |
| Shared Items          | The number of items that have been shared.     |

## Charts

Once a scan has data, the report charts the sharing links from several angles. A chart with nothing to show, such as Top External Recipients on a tenant that has no external shares, reads "No data to display" rather than sitting in a loading state. The last two charts are added once usage data has been synced.

| Chart                          | Shows                                                         |
| ------------------------------ | ------------------------------------------------------------- |
| Links by Classification        | The share of links that are anonymous, external, or internal. |
| Top Sites by Sharing Links     | The sites with the most sharing links.                        |
| Links by Type                  | The share of links by link type.                              |
| Top Libraries by Sharing Links | The libraries with the most sharing links.                    |
| Top External Recipients        | The external recipients appearing in the most shares.         |
| Storage Used (GB) by Workload  | Storage used across SharePoint, Teams, and OneDrive.          |
| Files by Workload              | File counts across SharePoint, Teams, and OneDrive.           |

## Filters

Buttons above the table apply common filters in one click:

| Filter               | Shows                                         |
| -------------------- | --------------------------------------------- |
| Anonymous            | Only anonymous links.                         |
| Anonymous + Editable | Only anonymous links that also allow editing. |
| Folder Shares        | Only shares placed on folders.                |
| External             | Only external links and shares.               |
| Internal             | Only internal links.                          |
| SharePoint           | Only items in SharePoint.                     |
| OneDrive             | Only items in OneDrive.                       |

## Table Details

The Sharing Links & External Shares table lists every sharing link and external share found. Selecting a row opens a details flyout with the item's full information, including its site, library, link scope and type, permission, password and expiry, the recipients it is shared with, and links to both the file and the sharing link itself.

| Column                  | Description                                           |
| ----------------------- | ----------------------------------------------------- |
| File Name               | The name of the shared file or folder.                |
| Item Type               | Whether the shared item is a file or a folder.        |
| Workload                | Where the item lives, such as SharePoint or OneDrive. |
| Site Name               | The site the item belongs to.                         |
| Drive Name              | The document library or drive the item is in.         |
| Classification          | Whether the link is Anonymous, External, or Internal. |
| Link Type               | The type of sharing link.                             |
| Link Scope              | Who the link is scoped to.                            |
| Roles                   | The access the link grants, such as read or write.    |
| Shared With             | The recipients the item is shared with.               |
| Has Password            | Whether the sharing link is password protected.       |
| Expiration Date Time    | When the link expires, if an expiry is set.           |
| Last Modified Date Time | When the item was last modified.                      |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Revoke Sharing Link</td><td>Removes the selected sharing link, so anyone using it loses access to the item.</td><td>true</td></tr><tr><td>Open File</td><td>Opens the shared file in a new browser tab.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}

# Permissions Report

The SharePoint Permissions Report shows how permissions are assigned across a single tenant's SharePoint and Teams sites and their document libraries. It draws attention to the grants most worth reviewing: those reaching the whole tenant, those given to external users, and Full Control given directly, along with libraries that have broken permission inheritance. The report requires a single tenant to be selected and is not available for All Tenants. Its data is compiled from a cached permission scan that you trigger and keep current from this page.

## Syncing Permission Data

The report reads from a cached scan rather than querying SharePoint live. The first time you open it for a tenant no data exists yet, and a prompt invites you to run a scan. The controls at the top of the page build and refresh that data.

| Control       | Description                                                                                                                                                                                                                                                                            |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sync data     | Queues a scan that reads site and document library permissions for the tenant. Progress is shown next to the button, and the report refreshes itself once the scan finishes. The scan reads permissions per library rather than per file, so it is far quicker than a sharing link scan. |
| Refresh       | The refresh icon reloads the report from the cached data without running a new scan. Use it when a scan has finished elsewhere, or when someone else has refreshed the cache.                                                                                                           |
| Export Report | Opens a preview of the report as a PDF, which you can then download. Greyed out until the report has data.                                                                                                                                                                              |

The last scan time is shown as "Last data refresh." If any sites could not be read during the last scan, a warning notes how many were skipped. Results from an earlier successful scan are kept where they exist, so those rows may be out of date, while sites never read successfully contribute nothing.

## Summary

Two rows of indicators summarize the tenant. The first row focuses on grants worth reviewing, and the second on the scan's coverage.

| Indicator              | Description                                                                                                                                          |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant-Wide Grants     | Permissions granted to a broad, everyone-style claim (such as Everyone, Everyone except external users, or All Users) that reaches the whole tenant. |
| External Grants        | Permissions granted to external (guest) users.                                                                                                       |
| Direct Full Control    | Full Control granted directly to a principal rather than through a SharePoint group.                                                                 |
| Detached Libraries     | Document libraries that hold their own unique permissions instead of inheriting from their site.                                                     |
| Sites Scanned          | The number of sites read in the scan.                                                                                                                |
| Libraries Scanned      | The number of document libraries read in the scan.                                                                                                   |
| Permission Assignments | The total number of permission assignments found.                                                                                                    |
| Sites Not Read         | The number of sites that could not be read during the scan.                                                                                          |

## Charts

Once a scan has data, three charts break the grants down visually.

| Chart                           | Shows                                                                          |
| ------------------------------- | ------------------------------------------------------------------------------ |
| Permissions by Level            | The share of grants at each permission level.                                  |
| Permissions by Principal Type   | The share of grants by the type of principal they were given to.               |
| Top Sites by Detached Libraries | The sites with the most libraries that have unique, non-inherited permissions. |

## Filters

Buttons above the table apply common filters in one click:

| Filter             | Shows                                                             |
| ------------------ | ----------------------------------------------------------------- |
| Tenant-Wide Grants | Only grants to broad, everyone-style claims.                      |
| External Grants    | Only grants to guest users.                                       |
| Full Control       | Only Full Control grants.                                         |
| Detached Libraries | Only rows for detached libraries that keep their own permissions. |
| Site Level         | Only site-level permissions.                                      |

## Table Details

The Library Permissions table lists the individual permission assignments. Libraries that still inherit their site's permissions are not listed, so every row is either a site's own permission or a deliberate exception to it.

| Column           | Description                                                                                                                                                                                               |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Site Name        | The site the permission is on.                                                                                                                                                                            |
| Applies To       | How far the permission reaches: Whole site for a site-level permission (also inherited by every library that still inherits), or This library only for a detached library that keeps its own permissions. |
| Library Title    | The document library the permission applies to, for library-level rows.                                                                                                                                   |
| Title            | The name of the user or group the permission is granted to.                                                                                                                                               |
| Principal Type   | The type of principal the permission was granted to, such as a user, a group, or a SharePoint group.                                                                                                      |
| Permission Level | The level of access granted, such as Read, Contribute, Edit, or Full Control.                                                                                                                             |
| Broad Claim      | When the grant is to a broad, everyone-style claim, the name of that claim; blank otherwise.                                                                                                              |
| Is Guest         | Whether the principal is an external (guest) user.                                                                                                                                                        |
| Email            | The email address of the principal, where available.                                                                                                                                                      |

{% include "../../../.gitbook/includes/feature-request.md" %}

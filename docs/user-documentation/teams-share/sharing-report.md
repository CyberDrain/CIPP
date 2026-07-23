# Sharing Report

This page is meant to give you an overview of what's being shared from SharePoint and OneDrive.

## Info Cards

* Sharing Links: Number of sharing links created in the tenant
* Anonymous Links: The number of sharing links that allow anonymous access
* External Links & Shares: The number of links and shares where access is granted to those external to the tenant
* Internal Links: The number of links only shared with internal users
* SharePoint Sites: The number of SharePoint sites in the tenant
* Teams-Connected Sites: The number of SharePoint sites linked to Microsoft 365 Teams
* OneDrive Accounts: The number of user accounts licensed for OneDrive
* Shared Items: The number of files/items that are shared via link
* Links by Classification: Shows the links by classification. The classifications are Anonymous, External, and Internal
* Top Sites by Sharing Links: The top ten SharePoint sites that have sharing links.
* Links by Type: This will show the links broken out by `sharingLink` type. See the [Microsoft documentation](https://learn.microsoft.com/en-us/graph/api/resources/sharinglink?view=graph-rest-1.0#type-options) for descriptions.&#x20;
* Storage Used (GB) by Workload: A chart showing how much storage is used across SharePoint, Teams, and OneDrive
* Files by Workload: A chart showing the number of files in each of SharePoint, Teams, and OneDrive

## Sharing Links & External Shares Table

### Table Details

| Column                  | Description                                                                                                                                                                                                 |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| File Name               | Name of the shared file or item the sharing link points to.                                                                                                                                                 |
| Item Type               | The kind of item shared (for example a file or a folder).                                                                                                                                                   |
| Workload                | The service the item lives in: `SharePoint` or `OneDrive`. Also used by the table's quick filters.                                                                                                          |
| Site Name               | The SharePoint site (or OneDrive account) hosting the item.                                                                                                                                                 |
| Classification          | Risk classification of the link's audience, derived from the link scope: `Anonymous` (red), `External` (amber), or `Internal` (green). Drives the colour coding and the Anonymous/External/Internal filters. |
| Link Type               | The kind of sharing link, mapped from the Graph `sharingLink` type facet — e.g. `view` (read-only), `edit` (read-write), or `embed`. Falls back to `link` when the type is unknown.                         |
| Roles                   | The permission role(s) the link grants (for example `read`, `write`, or `owner`). Rendered as a comma-joined list when multiple roles apply.                                                                |
| Shared With             | The recipients the item is shared with (list of identities). Typically empty for open anonymous links, which aren't scoped to specific people.                                                              |
| Expiration Date Time    | When the sharing link is set to expire. Shows `Never` in the row detail when no expiry is configured.                                                                                                       |
| Last Modified Date Time | When the sharing link or permission was last modified.                                                                                                                                                      |

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Revoke Sharing Link</td><td>Removes the sharing link so it can no longer be used. Anyone who currently has the link will immediately lose access to the file. You'll be asked to confirm before the link is revoked.</td><td>true</td></tr><tr><td>Open File</td><td>Opens the shared file in a new browser tab so you can review its contents before deciding whether to keep or revoke the link.</td><td>false</td></tr><tr><td>More Info</td><td>Opens Extended Info flyout</td><td>false</td></tr></tbody></table>

***

{% include "../../../.gitbook/includes/feature-request.md" %}

# Access Reports

Access Reports lists Microsoft's SharePoint Advanced Management access reports for a single tenant, starts new ones, and opens finished ones in CIPP. Use them to answer questions such as "which sites can this user reach?" across every SharePoint site or OneDrive in the tenant. Microsoft builds the reports, so reports started in the SharePoint admin center also appear here. The page requires a single tenant to be selected and is not available for All Tenants.

{% hint style="info" %}
Access reports need SharePoint Advanced Management in the tenant: either at least one Microsoft 365 Copilot licence assigned, or the SharePoint Advanced Management add-on. Without it, starting or listing a report returns an error saying so.
{% endhint %}

## Report Types

| Report           | Description                                                                                                       |
| ---------------- | ----------------------------------------------------------------------------------------------------------------- |
| Site permissions | Every SharePoint site (or OneDrive) in the tenant, with the users and groups that can reach it.                    |
| User permissions | Every SharePoint site (or OneDrive) the selected users can reach, and how they got access. Pick one or more users. |

For each report type, choose whether it covers SharePoint sites or OneDrive.

## Limits

Microsoft sets these limits, and they apply to reports started from CIPP and from the SharePoint admin center alike:

* The same report can be run again only once every 30 days. Starting a report from CIPP uses that allowance for the tenant.
* At most five user permissions reports can exist at once. Delete an old one to start another.
* The first site permissions report can take up to 5 days. Later reports usually finish within a day, and the data in them can be up to 48 hours old.

## Actions

| Action        | Description                                                                                                                               |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| New Report    | Starts a site permissions or user permissions report. Needs SharePoint write access.                                                      |
| View Report   | Opens a finished report as a table you can filter and export. Only shown once the report's status is Completed.                          |
| Delete Report | Deletes the report in the tenant. This frees a user report slot; it does not reset the 30-day wait. Needs SharePoint write access. |

## Table Details

| Column             | Description                                                        |
| ------------------ | ------------------------------------------------------------------ |
| Name               | The report's name. Reports started from CIPP are named after their type, workload and start time. |
| Report Type        | Site permissions or User permissions.                              |
| Workload           | SharePoint or OneDrive.                                            |
| Status             | Microsoft's status for the report, such as In progress or Completed. |
| Users              | For user permissions reports, the users the report covers.         |
| Requested Date Time | When the report was started.                                      |
| Created Date Time  | When Microsoft finished building the report.                       |

{% include "../../../../.gitbook/includes/feature-request.md" %}

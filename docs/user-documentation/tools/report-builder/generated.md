# Generated Reports

This page lists the reports that have been generated from your report templates, whether produced on demand or by a scheduled task. Each row is a completed report you can open, read on screen, or download as a PDF.

Generated reports are deleted automatically, together with their PDFs, once they are older than the period set under [Report Attachment Retention](../../cipp/settings/README.md#report-attachment-retention).

{% hint style="info" %}
A generated report is a snapshot, not a live view. Test results and database content are collected at the moment the report is generated and stored with it, so opening a report later shows the tenant as it was at that point. To see current data, generate the report again.
{% endhint %}

## Table Details

| Column        | Description                                                                                                                                                                                                                                  |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Template Name | The name of the template the report was generated from. A report produced by a schedule that carried no template name is recorded as `Scheduled Report`.                                                                                     |
| Tenant Filter | The tenant the report was generated for.                                                                                                                                                                                                     |
| Generated At  | The relative time since the report was generated.                                                                                                                                                                                            |
| Status        | The status of the generated report. The only value in use is `Completed`. A report that fails to generate is never recorded here at all, so failures show up as a missing report rather than a failed one, and the reason is in the logbook. |
| Sections      | The number of sections in the report.                                                                                                                                                                                                        |

Additional columns are available through the **Toggle Column Visibility** button at the top of the table, including separate counts of the test-backed and custom sections that make up the total.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Report</td><td>Opens the report, rendered as a PDF preview with a <strong>Download PDF</strong> option.</td><td>false</td></tr><tr><td>Delete</td><td>Permanently deletes the selected generated report. The template it was generated from is not affected.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
Deletion is immediate and cannot be undone. Where a report was produced for a client or an audit, download the PDF before removing it.
{% endhint %}

## Viewing a Report

The report opens rendered in full, using the page setup and branding that were in force when it was generated rather than your current settings. Reports generated before page setup existed fall back to the renderer's defaults, so an older report may not match the styling of a recent one produced from the same template.

**Download PDF** saves the report locally. The filename is built from the tenant and the current date.

{% include "../../../../.gitbook/includes/feature-request.md" %}

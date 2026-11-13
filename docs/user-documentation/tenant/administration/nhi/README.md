---
description: Every non-human identity compromise investigation, for every app and every tenant, in one place.
---

# NHI Compromise

The Non-Human Identity Compromise page lists every [NHI compromise investigation](case.md) CIPP has kept, for every app (enterprise application) and managed identity in the selected tenant, or across all tenants when **All Tenants** is selected. Each run is a case. Use this page to start investigations, to go back to one after the fact, to pull the evidence package for a completed run, or to see which queued runs have finished.

Runs are never expired automatically. A run stays, with its results, until it is deleted here.

## Action Buttons

### Start investigation

Select **Start investigation** and pick the apps or managed identities to investigate in **Apps or managed identities to investigate**. Each entry shows the app's name with its application ID, or **managed identity**. The button is greyed out while **All Tenants** is selected, because an investigation runs against one tenant; select a single tenant first. The panel's **Start investigation** button is greyed out until at least one app is picked.

* **One app** opens that app's case page and starts the run there, so you can watch it progress.
* **Several apps** queues one run per app and closes the panel once they are queued. The runs appear in the table as they finish.

A run compares the last 7 days against the 23 days before: the app's sign-ins and credentials, the changes made to it, what it changed in the directory, and the mail and files it reached. Sign-in checks need Microsoft Entra ID P1.

Runs can also be started with **Investigate compromise** on an enterprise application, or from the [App Permission Exposure](../../reports/app-permission-exposure.md) report.

## Filters

| Filter         | Shows                                     |
| -------------- | ----------------------------------------- |
| Critical cases | Runs with a Critical case level.          |
| High cases     | Runs with a High case level.              |
| Completed runs | Runs that finished collecting.            |

## Table Details

| Column                 | Description                                                                                                                                                       |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant                 | The tenant the run belongs to.                                                                                                                                    |
| Display Name           | The investigated app or managed identity.                                                                                                                         |
| Service Principal Type | Whether it is an application or a managed identity.                                                                                                               |
| Level                  | The case level: Critical, High, Medium or Low. It combines the evidence level with the impact of the app's access. Empty while the run is waiting or when it failed. |
| Evidence Level         | How strong the evidence of a compromise is: High, Medium or Low.                                                                                                  |
| Impact                 | The highest impact of the app's access, as rated by the [App Permission Exposure](../../reports/app-permission-exposure.md) report.                               |
| Score                  | The evidence score behind the evidence level. The breakdown is on the case.                                                                                       |
| Status                 | **Waiting** while queued, **Running**, **Completed**, or **Error** with the reason in the details panel.                                                          |
| Extracted At           | When the data was collected.                                                                                                                                      |
| Requested By           | Who started the run.                                                                                                                                              |
| Containment Runs       | How many times containment was run against the case. Releases are not counted.                                                                                    |
| Case Id                | The case ID. It appears on every logbook line the run, its containment and its exports produced, so the Logbook can be filtered to a single case.                |

The details panel also shows the app's application ID, when the run was requested, the error message for a failed run and **Incomplete Count**: the number of checks that did not collect in full, for example because a licence was missing or a cap was reached. The case page shows which ones.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Open case</td><td>Opens the run on the <a href="case.md">NHI case</a> page, exactly as it was collected. A queued or running case shows its live progress, and a failed one its error. Containment and the evidence package for the case are available from there.</td><td>false</td></tr><tr><td>Download evidence (ZIP)</td><td>Builds the evidence package for the run and downloads it, without opening the case. Greyed out until the run has completed.</td><td>true</td></tr><tr><td>Delete run</td><td>Removes the run and its results permanently. The logbook entries stamped with the case ID are not removed. Greyed out without the <code>Tenant.Application.ReadWrite</code> permission.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
Everything a run holds is metadata: sign-ins, credentials, owners, permissions, directory audits and unified audit log records. No message body or file content is collected, stored or exported.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

---
description: Every Business Email Compromise run, for every user and every tenant, in one place.
---

# Business Email Compromise

The Business Email Compromise page lists every [Compromise Remediation](case.md) run CIPP has kept, for every user in the selected tenant, or across all tenants when **All Tenants** is selected. Each run is a case. Use this page to start investigations, to go back to one after the fact, to pull the report or the evidence package for a run completed weeks ago, or to see which queued runs have finished.

Runs are never expired automatically. A run stays, with its results, until it is deleted here or from the user's run history.

## Action Buttons

### Start investigation

Select **Start investigation** and pick the users to investigate in **Users to investigate**. The button is greyed out while **All Tenants** is selected, because an investigation runs against one tenant; select a single tenant first. The panel's **Start investigation** button is greyed out until at least one user is picked.

* **One user** opens that user's case page and starts the run there, so you can watch it progress.
* **Several users** queues one run per user, tracked together under one entry on the Queue page, and closes the panel once they are queued. The runs appear in the table as they finish.

Runs can also be queued with **BEC Remediation** on the [Users](../users/README.md) page, or started by an alert.

### All runs and By user

The toggle next to **Start investigation** switches between two views of the same runs.

| View     | Description                                                                                                                                                                                                  |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| All runs | One row per run.                                                                                                                                                                                             |
| By user  | One row per user, sorted with the most serious first. **Level** is the worst level of any of the user's runs; the score, status and date come from the latest run. **View runs** lists every run for that user. |

## Filters

| Filter            | Shows                                                                                          |
| ----------------- | ---------------------------------------------------------------------------------------------- |
| High threat level | Runs with a High threat level. In **By user**, every user with at least one High run.          |
| Completed runs    | Runs that finished collecting. In **By user**, users whose latest run has completed.            |

## Table Details

| Column              | Description                                                                                                                                              |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant              | The tenant the run belongs to.                                                                                                                           |
| User Principal Name | The investigated user.                                                                                                                                   |
| Level               | The threat level CIPP assigned: High, Medium or Low. Empty while the run is waiting or when it failed.                                                   |
| Run Count           | **By user** only. How many runs the user has.                                                                                                            |
| Score               | The threat score behind the level. The breakdown is on the run itself.                                                                                   |
| Status              | **Waiting** while queued or running, **Completed**, or **Error** with the reason in the details panel.                                                   |
| Extracted At        | When the data was collected.                                                                                                                             |
| Requested By        | **All runs** only. Who queued the run, or the alert engine when an alert started it.                                                                     |
| Containment Runs    | **All runs** only. How many times containment was run against the case.                                                                                  |
| Case Id             | **All runs** only. The case ID. It appears on every logbook line the run, its containment and its exports produced, so the Logbook can be filtered to a single case. |

The details panel also shows the user's display name, when the run was requested, the error message for a failed run and, in **All runs**, **Incomplete Count**: the number of data sources that did not collect in full, for example because a licence was missing or a cap was reached. The case page shows which ones.

## Table Actions

In **All runs**, and on each row under **View runs**:

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Open case</td><td>Opens the run on the <a href="case.md">Compromise Remediation</a> page, exactly as it was collected. A queued or running case shows its live progress, and a failed one its error. From there the PDF report, the JSON and the evidence package can be produced, and containment run, for that case.</td><td>false</td></tr><tr><td>Download evidence (ZIP, with PDFs)</td><td>Renders both report PDFs in the browser, builds a fresh evidence package from the stored run around them and downloads it, without opening the case. Greyed out until the run has completed.</td><td>true</td></tr><tr><td>Delete run</td><td>Removes the run, its results and its evidence package permanently. The logbook entries stamped with the case ID are not removed.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

In **By user**:

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View runs</td><td>Lists every run for the user, newest first, each with the actions above.</td><td>true</td></tr><tr><td>Open latest case</td><td>Opens the user's latest run on the <a href="case.md">Compromise Remediation</a> page.</td><td>false</td></tr><tr><td>Download latest evidence (ZIP, with PDFs)</td><td>Downloads the evidence package for the user's latest run. Greyed out until that run has completed.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
Everything a run holds is metadata: audit records, sign-ins, directory audits, message-trace headers, permissions, consents, rules and devices. No message body, attachment or file content is collected, stored or exported.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

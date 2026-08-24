---
description: Every Business Email Compromise run, for every user and every tenant, in one place.
---

# BEC Reports

The BEC Reports page lists every [Compromise Remediation](../administration/users/user/bec.md) run CIPP has kept: one row per case, for every user in the selected tenant, or across all tenants when **All Tenants** is selected. It is where to go back to an investigation after the fact, to pull the report or the evidence package for a run completed weeks ago, or to see which runs queued from the Users page have finished.

Runs are never expired automatically. A run stays, with its results, until it is deleted here or from the user's run history.

## Columns

| Column            | Description                                                                                                                                       |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant            | The tenant the run belongs to.                                                                                                                    |
| UserPrincipalName | The investigated user.                                                                                                                            |
| Level             | The threat level the server assigned: High, Medium or Low. Empty while the run is waiting or when it failed.                                      |
| Score             | The threat score behind the level. The breakdown is on the run itself.                                                                            |
| Scope             | **Full** for every run since the investigation became full-only; **Quick** on older runs that collected only the classic eleven checks.           |
| Status            | **Waiting** while queued or running, **Completed**, or **Error** with the reason in the details panel.                                            |
| ExtractedAt       | When the data was collected.                                                                                                                      |
| RequestedBy       | Who queued the run, or the alert engine when an alert started it.                                                                                 |
| ContainmentRuns   | How many containment runs were recorded on the case.                                                                                              |
| HasEvidence       | Whether evidence has been exported for the run at least once. Every export's hash, time and size are recorded on the run; the latest is in the details panel.                             |
| CaseId            | The case id. It appears on every logbook line the run, its containment and its exports produced, so the Logbook can be filtered to a single case. |

The filters at the top narrow the list to High threat levels or completed runs.

## Actions

| Action                          | Description                                                                                                                                                                                                                |
| ------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| View run                        | Opens the user's Compromise Remediation page showing this run exactly as it was collected. From there the PDF report, the JSON and the evidence package can be produced, and containment run, for that case.               |
| Download evidence package (ZIP) | Builds a fresh evidence package from the stored run (without the PDF report, which only the browser can render) and downloads it. Every export is hashed and recorded on the run; compare a copy's SHA-256 with its recorded export before relying on it. |
| Delete run                      | Removes the run, its results and its evidence package permanently. The logbook entries stamped with the case id are not removed.                                                                                           |

{% hint style="info" %}
Everything a run holds is metadata: audit records, sign-ins, directory audits, message-trace headers, permissions, consents, rules and devices. No message body, attachment or file content is collected, stored or exported.
{% endhint %}

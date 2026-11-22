---
description: Copy a departed user's OneDrive to other users or a document library, and follow each copy's progress.
---

# OneDrive Copies

This page lists every OneDrive copy started in the selected tenant, with who started it, where it is going and how far it has got. Use **Copy OneDrive** to start a new one: the departed user's OneDrive is copied into a folder named after them in each selected user's OneDrive, a document library, or both. Files already at the destination are kept.

{% hint style="info" %}
CIPP does not copy the files itself. It starts SharePoint copy jobs, the same ones SharePoint's own **Copy to** uses, and reports what SharePoint returns. How long a copy takes, and any file SharePoint fails to copy, are outside CIPP's control. Shortcuts to other people's files are not copied.
{% endhint %}

## Starting a copy

| Field                        | Description                                                                                                                      |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| User whose OneDrive is copied | The departed user. Only accounts that are blocked from signing in are listed, so block the account first.                        |
| Copy to users                | One or more users who each receive a copy in their own OneDrive.                                                                 |
| Copy to a document library   | A SharePoint site, a document library on it, and an optional folder to copy into. Can be used instead of, or as well as, users. |
| Include version history      | Copies earlier versions of each file as well as the current one.                                                                 |

Each user you copy to needs a OneDrive licence, a OneDrive that has already been set up, and enough free space. Remove the departed user's licences only once the copy shows **Completed**.

## Table Details

| Column            | Description                                                                 |
| ----------------- | --------------------------------------------------------------------------- |
| Started Utc       | When the copy was started.                                                  |
| Leaver            | The user whose OneDrive is being copied.                                    |
| Destinations      | Where the copy is going.                                                    |
| State             | Queued, In Progress, Completed or Failed. Completed and Failed are final.   |
| Started By        | The CIPP user who started the copy.                                         |
| Source File Count | The number of files in the OneDrive when the copy started.                  |
| Source Bytes      | The size of the OneDrive when the copy started.                             |
| Last Checked Utc  | When CIPP last asked SharePoint for the copy's progress.                    |

Select a copy to see its progress for each destination, with the files and data copied so far and any errors SharePoint reported. CIPP checks SharePoint for a copy's progress at most every 30 minutes.

{% include "../../../.gitbook/includes/feature-request.md" %}

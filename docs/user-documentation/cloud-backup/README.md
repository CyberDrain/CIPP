---
icon: cloud-arrow-up
---

# Cloud Backup

Cloud Backup copies the content of your tenants' Microsoft 365 services to storage you own, on a schedule you choose. Backups go to an Azure storage account or an Amazon S3 (or S3-compatible) bucket, so they stay available even if a tenant or CIPP itself is lost.

## What is backed up

| Service | What is included |
| --- | --- |
| Exchange Online | User and shared mailboxes: mail, calendar and contacts. Mail messages are also stored as `.eml` files. |
| OneDrive | The files in every user's OneDrive. |
| SharePoint | The files in every document library of every site, including the sites behind Microsoft Teams. |
| Teams | Chats and channel messages, with images pasted into them. Teams messages can be backed up but not restored into Teams. |

A policy backs up everything in the services you choose, and picks up new users, mailboxes and sites automatically. You can leave out users, members of groups and sites with [exclusions](policies.md#exclusions).

The first backup copies everything. Later backups only copy what was added, changed or deleted since the previous one. When an item changes or is deleted in Microsoft 365, the earlier copy is kept in the destination for as long as the policy says.

Use [Browse & Restore](restore.md) to find backed up items at any point in time, download them, restore mail and files to Microsoft 365, or export them as a `.zip` file.

## Getting started

1. Add a [destination](destinations.md): the storage account or bucket backups are written to. Versioning must be turned on for it.
2. Add a [policy](policies.md): which tenants and services to back up, how often, and how long to keep earlier versions. CIPP grants itself the permissions it needs in each tenant when you save.
3. Check the [runs](runs.md) to see each backup's result.
4. Find and restore items in [Browse & Restore](restore.md), and follow restores and exports in [Restore History](history.md).

## Overview

The Cloud Backup overview shows how many policies and destinations you have, how many tenants are covered and how many backups failed in the last 24 hours. The **By service** table shows, for each service, how many mailboxes, OneDrives, sites or teams are backed up, how many items and how much data the latest runs stored, and the latest result. The last table lists the latest backup for every tenant, policy and service.

{% include "../../../.gitbook/includes/feature-request.md" %}

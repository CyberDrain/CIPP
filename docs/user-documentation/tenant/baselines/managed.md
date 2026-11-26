---
description: Baselines maintained by CyberDrain, published for everyone or built for your MSP
---

# Managed Baselines

{% hint style="warning" %}
**Closed beta.** Managed Baselines is in closed beta. The **Managed** tab and the integration already appear in CIPP, but only MSPs in the beta can use the service until it opens to everyone.
{% endhint %}

Managed Baselines is a paid CyberDrain service. CyberDrain's engineers publish baselines you can add to your own, and on request build one custom baseline for your MSP. Either way the result is an ordinary baseline: you review it, choose its tenants, and decide when to take CyberDrain's later changes.

{% hint style="info" %}
Until the [CyberDrain Managed Baselines](../../cipp/integrations/managed-baselines.md) integration is enabled, this page explains the service and links to the integration. Once it is enabled, the page offers the three options described below.
{% endhint %}

## Managed Baseline Template

Lists the baselines CyberDrain publishes.

### Table Details

| Column     | Description                                                                                                  |
| ---------- | ------------------------------------------------------------------------------------------------------------ |
| Name       | The name of the published baseline.                                                                          |
| Description | What the baseline is for.                                                                                   |
| Tags       | What the baseline is aimed at, such as an industry, a region or a size of client.                            |
| Standards  | How many standards it carries across all of its stages.                                                      |
| Version    | The version CyberDrain currently publishes.                                                                  |
| Updated At | When CyberDrain last changed it.                                                                             |
| Status     | **Imported** once you have added it, and **Update available** when CyberDrain has published a newer version. |

Selecting a row opens the **Managed Baseline Details** flyout. The **Details** tab lists the standards in each stage. The **Guide** tab holds the implementation guide, described under [Implementation Guide](#implementation-guide).

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Add to My Baselines</td><td>Adds the baseline to your own. It arrives assigned to a placeholder, so nothing runs until you assign tenants in the editor. Offered until the baseline has been added.</td><td>true</td></tr><tr><td>Edit Baseline</td><td>Opens your copy in the <a href="template.md">baseline editor</a>. Offered once the baseline has been added.</td><td>false</td></tr></tbody></table>

## Custom Managed Baseline

Lists the baselines you have asked CyberDrain to build, with where each request stands. A custom baseline is built for your MSP as a whole, to use across your clients, and not once for every tenant. **Request Custom Baseline** opens a drawer to start a new one.

### Requesting a Baseline

| Field                              | Description                                                                                                                                     |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| Typical tenant to snapshot | A tenant that is typical for your clients. CIPP compares it against every available standard to give the engineer a starting point. The tenant itself is never sent to CyberDrain. |
| Main industry of your clients | The industry most of your clients are in. Pick one from the list or type your own. |
| Typical client size | The usual number of seats, as a range. |
| What do you expect from this baseline? | What you expect the baseline to deliver across your clients. Say whether to start in report only or to remediate straight away. |
| Which exceptions must exist? | Exceptions the baseline has to allow for, such as devices that still need basic authentication. Describe the kind of thing, not the people or addresses involved. |
| Frameworks your clients have to meet | Any frameworks the baseline should line up with. Pick from the list or type your own. |
| Anything else we should know? | Anything else the engineer should know. |

{% hint style="warning" %}
What you type is sent to CyberDrain as you typed it. The request is refused when it contains an email address, an IP address, an ID, or the tenant's own name or domains, so describe things instead of naming them. The domain of a product your clients use is allowed.
{% endhint %}

### Statuses

| Status                       | Meaning                                                                                                              |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Waiting on data collection   | CIPP is comparing the tenant against every standard. The details flyout shows how many have been compared.            |
| Waiting on CyberDrain        | The result was sent and an engineer is building the baseline. CIPP checks for an answer every hour.                  |
| Completed - ready to confirm | The baseline has been delivered and is waiting for you to review it.                                                 |
| Implemented                  | You saved the delivered baseline. **Update available** appears beside it when CyberDrain later revises the baseline. |
| Failed                       | Collecting or sending did not finish. The details flyout gives the reason, and **Retry** starts again.               |

### Table Details

| Column       | Description                                              |
| ------------ | -------------------------------------------------------- |
| Requested    | When the request was made.                               |
| Tenant       | The tenant that was snapshotted. Kept in your CIPP only. |
| Industry     | The industry you entered.                                |
| Client Size  | The size you selected.                                   |
| Status       | Where the request stands.                                |
| Last Checked | When CIPP last asked CyberDrain about the request.       |
| Baseline     | The baseline the request became, once it is implemented. |

Selecting a row opens the **Custom Baseline Request** flyout. It shows everything you entered, any notes from the engineer, and exactly what was sent to CyberDrain. Once the baseline has been delivered, a **Guide** tab holds its implementation guide.

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Review and Confirm</td><td>Opens the delivered baseline in the <a href="template.md">baseline editor</a> with the tenant already selected. Nothing is saved, and no tenant is touched, until you save it there. Offered once the request is ready to confirm.</td><td>false</td></tr><tr><td>Refresh Status</td><td>Asks CyberDrain where the request stands straight away.</td><td>true</td></tr><tr><td>Retry</td><td>Compares the tenant again and sends the result. Offered for a failed request.</td><td>true</td></tr><tr><td>Cancel Request</td><td>Tells CyberDrain to stop working on the request and removes it from the list. Not offered once the request is implemented.</td><td>true</td></tr></tbody></table>

## Recommendations

Shows which of CyberDrain's recommended standards apply to a tenant. You pick the ones you want and CIPP builds a baseline from them.

CyberDrain's service supplies the list of recommendations. CIPP compares the tenant against each one and shows only those the tenant differs on. The comparison runs in your own CIPP, and nothing about the tenant is sent to CyberDrain.

Conditional Access is not part of the recommendations yet.

### Scanning a Tenant

1. Select **Recommendations** on the Managed Baselines page.
2. Choose the tenant in the tenant selector at the top of the page and select **Scan**, which names that tenant.
3. The recommendations are added as they are compared, and the page shows how many are done.

A tenant is only scanned when you select **Scan**. After a scan the page shows how many recommendations are new and how many were resolved since the scan before.

### Table Details

| Column         | Description                                   |
| -------------- | --------------------------------------------- |
| Recommendation | The standard that is recommended.             |
| Category       | The category of the standard.                 |
| Impact         | The impact of the recommendation.             |
| Frameworks     | The frameworks the standard is part of.       |
| Status         | See the statuses below.                       |
| Differs On     | The settings that are not as recommended.     |
| First Seen     | The date of the scan that first found it.     |

Select a row to see why CyberDrain recommends it, and the current and the recommended value.

### Statuses

| Status                | Meaning                                                                                |
| --------------------- | -------------------------------------------------------------------------------------- |
| Recommended           | The tenant differs from the recommendation and no baseline assigned to it covers this. |
| Covered by a baseline | The tenant differs, but a baseline assigned to it already holds this standard.         |

A recommendation the tenant already meets, or has no licence for, is not shown.

### Generating a Baseline

**Generate Baseline for All Recommendations** takes every Recommended row. To use only some, tick those rows and choose **Generate Baseline for Selection** from the bulk actions, or choose it from the menu of a single row. Either way the baseline editor opens with the scanned tenant selected and the chosen standards in one stage, all with remediation off. Nothing is saved until you save in the editor.

## Implementation Guide

Every managed baseline can come with a guide written by CyberDrain. It opens from the **Guide** tab of the details flyout, both on this page and for a managed baseline on the [Baselines](./) tab.

| Part                   | Description                                                                                                                              |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Implementation Guide   | What the baseline is for, what to check before you start and how to roll it out.                                                         |
| Stage guidance         | For each stage, in rollout order: what changes, what users notice and what to prepare.                                                   |
| Communication Examples | For each stage, messages you can send to your client or their staff. The copy button copies the text so you can paste it into your mail. |

The guide always belongs to the version CyberDrain currently publishes. When your copy is on an older version, the guide says so.

## Keeping a Managed Baseline Up to Date

A managed baseline sits on the [Manage Baselines](templates.md) page with all of your other baselines, where the **Managed by CyberDrain** filter finds it. Two extra actions bring in CyberDrain's later changes. Both show what will change before anything is written.

| Action                         | What it does                                                                                                                                                                                                                                              |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Align with CyberDrain baseline | Replaces every standard and the stage layout with CyberDrain's. Standards only you have are removed. The name, description, assigned tenants, exclusions and alert settings stay as they are.                                                            |
| Merge with CyberDrain baseline | Overwrites the standards you both have with CyberDrain's settings and leaves the standards only you have untouched. Standards only CyberDrain has are listed with a tick box each, and only the ones you tick are added. Your stages are not changed. |

Both actions also bring the Conditional Access, Intune and other templates their standards refer to up to CyberDrain's version, replacing any edits you made to those templates.

A managed baseline cannot be saved to GitHub. A clone of it is an ordinary baseline and can be.

## What Is Sent to CyberDrain

A custom request sends what you typed on the form and, for every standard, whether the tenant is compliant with CIPP's default settings and the current value of each setting that standard checks.

Before anything is stored or sent, CIPP removes what could identify the tenant:

* Any text containing a domain name, an email address, an IP address or an ID.
* Any text containing the tenant's own name, domains or tenant ID.
* Every list, such as a list of users or mailboxes that break a rule. Only how many entries it has is kept, unless every entry is an on or off value, a number, or one of CIPP's own setting values.
* Any text longer than 200 characters. Only its length is kept.

Standards that deploy a template you choose, or that need a value only you can decide, are reported as **Needs a choice** and nothing is read from the tenant for them.

The request carries no tenant ID, domain or name. CyberDrain knows which partner sent a request, and not which tenant the snapshot came from.

{% hint style="info" %}
Short text that matches none of the patterns above, such as a custom word in a setting, is sent as it is. The details flyout of every request shows exactly what was sent.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

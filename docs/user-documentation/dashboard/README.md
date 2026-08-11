---
description: About the Dashboard which includes versions and quick links
icon: house
---

# CIPP Dashboard

Welcome to the CIPP Dashboard. This page gives you both an overview of your client tenants and a way to assess them against security baselines. It is laid out in tabs, with different information on each.

What the dashboard shows depends on the tenant selector. Choose a single tenant and you get that tenant's detail. Choose **All Tenants**, which is also where you land before picking a tenant, and the page swaps to an estate-wide view.

{% hint style="warning" %}
Much of the dashboard is built from data cached in CIPP's reporting database, refreshed by a scheduled job. The first time you load the dashboard for a tenant you may see little or nothing until that job has run. Use **Refresh** to collect the data immediately rather than waiting.
{% endhint %}

## Walkthrough

{% @storylane/embed subdomain="app" url="https://app.storylane.io/share/zt4porabti6d" linkValue="zt4porabti6d" %}

## All Tenants View

Under All Tenants the dashboard is built entirely from cached data, with no live Graph calls, and is organized into three bands. Almost every figure links through to the page where you can investigate it.

### Portfolio

A row of totals for tenants, users, mailboxes, and devices under management, each with the per-tenant average on hover. Selecting a tile opens the matching list page across all tenants.

If the cache has never run, a note appears here in place of the figures.

### Security Posture

<details>

<summary>Secure score</summary>

The portfolio average, how many tenants it covers, and the movement since the previous measurement, along with the best and worst scoring tenants. **View** opens the [securescore](../tenant/administration/securescore/ "mention") page, which shows a full estate view under All Tenants.

</details>

<details>

<summary>Identity posture</summary>

How many of your tenants are failing at least one identity check, followed by the checks failing across the most tenants. Counts are of tenants rather than users. **View** opens the [identity.md](identity.md "mention") tab.

</details>

<details>

<summary>Mail hygiene</summary>

SPF, DKIM, DMARC, and DNSSEC coverage across the domains that have been analyzed, shown as coverage meters with the domain count. **View** opens the [domains-analyzer](../tenant/standards/domains-analyzer/ "mention").

</details>

<details>

<summary>Standards alignment</summary>

The portfolio average alignment score, with tenants grouped into bands of 90% and above, 75 to 89%, 50 to 74%, and below 50%. **View** opens the [alignment](../tenant/standards/alignment/ "mention") page.

</details>

### Operations and Triage

Four tiles cover what needs attention right now.

| Tile                                   | Description                                                                                                                                                    |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenants logging errors today           | Tenants with Error or Critical log entries today, with the total entry count. Opens the [logs](../cipp/logs/ "mention").                                       |
| Delegations expiring within 30 days    | GDAP delegations nearing expiry, noting how many of those have no auto-extend. Opens GDAP [relationships](../tenant/gdap-management/relationships/ "mention"). |
| High-risk checks failing               | High-risk test failures and how many tenants they span. Opens the [identity.md](identity.md "mention") tab.                                                    |
| Standards deviations awaiting approval | Deviations pending approval and the number of tenants involved. Opens [alignment](../tenant/standards/alignment/ "mention").                                   |

Below the tiles, three cards surface the tenants behind those numbers.

<details>

<summary>Tenants needing attention</summary>

Tenants ranked worst first by delegation state and error activity, so the ones in trouble surface without hunting.

</details>

<details>

<summary>Delegation expiry horizon</summary>

GDAP and CSP relationships grouped by time remaining: expired, 0 to 7 days, 8 to 30 days, 31 to 90 days, and over 90 days.

</details>

<details>

<summary>Cache freshness</summary>

Counts of tenants that are fresh, stale, or never cached, alongside the tenants that have not synced recently. This catches tenants that quietly stopped collecting data, which would otherwise show as misleadingly clean elsewhere on the dashboard.

</details>

The Identity, Devices, and Custom tabs also switch to cross-tenant views under All Tenants.

## Overview Tab

With a single tenant selected, the Overview tab opens with a row of controls, then the tenant's detail cards.

### Page Controls

<details>

<summary>Portals</summary>

Quick links to the Microsoft portals for the selected tenant. Which portals appear is controlled by the **Portal Links Configuration** settings on the [user-settings.md](../shared-features/menu-bar/user-settings.md "mention") page.

{% hint style="warning" %}
These links take you out of CIPP, and require your own account, not the CIPP service account, to hold GDAP permissions for the resource.
{% endhint %}

</details>

<details>

<summary>Executive Summary</summary>

Generates a client-friendly summary report from CIPP's data, suitable for presenting to the client. It is fully brandable via [branding.md](../cipp/settings/branding.md "mention"), and you can choose which sections to include before generating.

</details>

<details>

<summary>Report Builder</summary>

Opens the [report-builder](../tools/report-builder/ "mention"), where you can use the data collected by CIPP's test suites to produce custom client-facing reports.

</details>

{% hint style="info" %}
On narrower screens **Executive Summary** and **Report Builder** collapse into a single **Dashboard Reports** menu.
{% endhint %}

### Test Suite Controls

The test suite you select drives the assessment figures on this tab and the contents of the Identity, Devices, and Custom tabs.

<details>

<summary>Select a test suite</summary>

Choose which suite to assess the tenant against. Custom suites you have created are listed alongside the built-in ones. The refresh icon beside the box reloads the list of suites, which is useful after creating one.

The dashboard opens on your preferred suite, falling back to the instance-wide preference and then to Zero Trust Network Access if neither has been set. To choose your preferred starting suite, set **Default test suite on the Home page** on the [user-settings.md](../shared-features/menu-bar/user-settings.md "mention") page.

</details>

<details>

<summary>Create Suite</summary>

Build your own suite by selecting from the available Identity, Device, and Custom tests. Give it a name and description, choose the tests, and it becomes selectable alongside the built-in suites.

</details>

<details>

<summary>Refresh</summary>

Collects fresh data for the tenant. You are asked what to refresh:

| Mode                                       | Description                                                 |
| ------------------------------------------ | ----------------------------------------------------------- |
| Cache & Tests (full refresh)               | Collects tenant data and then re-runs the tests against it. |
| Cache only (collect tenant data)           | Refreshes the collected data without re-running tests.      |
| Tests only (re-run against existing cache) | Re-runs the tests against the data already collected.       |

A full refresh can take up to two hours. Tests-only is much faster where the cache is already populated. The work runs in the background, so you may need to return to the dashboard once it completes.

</details>

<details>

<summary>Edit</summary>

Edits the selected custom test suite. Built-in suites cannot be edited, and the button is unavailable when one is selected.

</details>

<details>

<summary>Delete</summary>

Deletes the selected custom test suite. Built-in suites cannot be deleted, and the button is unavailable when one is selected. Deletion cannot be undone.

</details>

### Available Built-In Test Suites

* **ACSC Essential Eight**: Australian Cyber Security Center (ACSC) Essential Eight Maturity Model, eight mitigation strategies for adversary defense covering MFA, restricting administrative privileges, application control, patching applications and operating systems, Microsoft Office macro settings, user application hardening, and regular backups. CIPP tests cover what the Microsoft 365, Entra, Intune, and Defender APIs expose; lower-level enforcement controls that cannot be validated from cloud telemetry are flagged as manual.
* **CIS Microsoft 365 Foundations Benchmark v7.0.0**: Center for Internet Security (CIS) Microsoft 365 Foundations Benchmark v7.0.0, a prescriptive technical baseline for securely configuring a Microsoft 365 tenant across the M365 admin center, Defender, Purview, Intune, Entra, Exchange Online, SharePoint, and Teams.
* **CISA ScubaGear Tests for Exchange Online**: Security configuration assessment tests based on CISA's Secure Cloud Business Applications (ScubaGear) project for Microsoft Exchange Online. These tests validate compliance with federal security baselines.
* **EIDSCA (Entra ID Security Configuration Analyzer) Tests**: Comprehensive security assessment for Microsoft Entra ID covering authorization policies, authentication methods, consent policies, password policies, and group settings. Based on Microsoft's EIDSCA framework for identity security best practices.
* **Generic Tenant Tests**: Executive-level informational reports covering licensing, MFA posture, secure score trends, and tenant capabilities. These tests provide a clear snapshot of your tenant's current state without pass/fail criteria.
* **Microsoft 365 Copilot Readiness Tests**: Assess tenant readiness for Microsoft 365 Copilot deployment. Tests cover prerequisite licensing, Copilot license assignment, and active M365 app usage that determines which users would benefit most from Copilot.
* **ORCA (Office 365 Recommended Configuration Analyzer) Tests**: Comprehensive security assessment for Microsoft Exchange Online and Office 365 security configurations. Tests cover anti-spam, anti-phish, anti-malware, safe links, safe attachments, DKIM, transport rules, and other Exchange Online security settings.
* **SMB1001:2026 Cybersecurity Standard**: Dynamic Standards International (DSI) SMB1001:2026, a multi-tiered cybersecurity certification for small and medium-sized businesses, prescribing a five-level pathway across Technology Management, Access Management, Backup and Recovery, Policies/Processes/Plans, and Education and Training. CIPP tests cover the technical controls implementable against a Microsoft 365 tenant (Identity) and via Intune-managed workstations (Devices).
* **Zero Trust Network Access Tests**: Microsoft's comprehensive security assessment covering identity and device compliance, conditional access policies, authentication methods, and endpoint protection aligned with Zero Trust principles.

### Dashboard Cards

<details>

<summary>Tenant</summary>

The tenant's name, tenant ID, and primary domain. The tenant ID can be copied to the clipboard.

</details>

<details>

<summary>Tenant metrics</summary>

Counts of Users, Guests, Groups, Service Principals, Devices, and Managed devices.

{% hint style="info" %}
Each metric is clickable and takes you to the corresponding area of CIPP for a deeper look.
{% endhint %}

</details>

<details>

<summary>Assessment</summary>

How the tenant scored against the selected test suite, broken down by Identity, Devices, and Custom, with an overall figure and a pass, fail, and skip split. The suite's name and description are shown on the card.

</details>

<details>

<summary>Alerts</summary>

Alerts generated for the tenant, with counts for Active and Snoozed. Switch between the two to filter the list, and use the clock icon on a row to snooze an alert or remove an existing snooze. **Manage** opens the [alert-configuration](../tenant/administration/alert-configuration/ "mention") page.

</details>

<details>

<summary>Secure Score</summary>

The historical trend of the Microsoft Secure Score collected for the tenant.

</details>

<details>

<summary>User authentication</summary>

A chart of user authentication and MFA or Conditional Access status.

</details>

<details>

<summary>All users auth methods</summary>

The authentication methods in use across the tenant's users. Clicking a category jumps to the MFA report with filtering applied, so you can see exactly which users are on that method and who needs moving to something stronger.

</details>

<details>

<summary>License Overview</summary>

The licenses present on the tenant, with assigned and available counts.

{% hint style="info" %}
To exclude a license from this and all other reports in CIPP, add the license in licenses.md.
{% endhint %}

</details>

## Other Tabs

The [identity.md](identity.md "mention"), [devices.md](devices.md "mention"), and [custom.md](custom.md "mention") tabs show the results of the test suite selected on this tab, including remediation guidance for failed tests. Each has its own page in this documentation.

**Previous Dashboard Experience** returns you to the [dashboard.md](dashboard.md "mention").

{% include "../../../.gitbook/includes/feature-request.md" %}

---
description: Standards ensure consistent configuration across your Microsoft 365 tenants.
---

# Standards & Drift

{% hint style="warning" %}
#### Page Purpose

This page serves as an overview of CIPP Standards. For the technical components of each page and details on the actions you can take, please see the respective docs page under this menu item to the left.
{% endhint %}

## Standards Overview

Standards keep your Microsoft 365 tenants configured the way you intend, by checking their settings on a schedule and acting when they do not match. This catches configuration that has been changed by hand, inherited from a tenant you took over, or never set correctly in the first place.

CIPP offers two ways of doing this, and they suit different jobs.

### Standards

The traditional approach. You build a template describing how tenants should be configured, apply it, and CIPP enforces it **every twelve hours**. Each standard in the template is set to Report, Alert, or Remediate, so a single template can quietly gather data on some settings while actively correcting others.

Use standards when you want a configuration applied and kept that way without asking.

### Drift

Drift takes the opposite stance: instead of silently correcting a tenant, it tells you what changed and lets you decide. A drift template is evaluated **every twelve hours** and any setting that no longer matches is raised as a deviation for review, which you can then accept or deny.

Use drift when a client's configuration needs a lighter touch, when you want visibility before anything is changed, or when you need an audit trail of what moved and who signed it off.

| Constraint              | Detail                                                                                                           |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------- |
| One template per tenant | A tenant can have only one drift template applied at a time, unlike standards templates which merge.             |
| Actions                 | Drift standards are set to Report. Enabling automatic remediation on a standard makes it Report and Remediate.   |
| Alerting                | Configured on the template itself, through the drift alert webhook and email settings, rather than per standard. |
| Scheduling              | Drift templates always run on the schedule. The "Do not run on schedule" option is unavailable.                  |

{% hint style="info" %}
For a deeper dive on the differences between the two and considerations for when to use each, see [standards-v-drift.md](../../../troubleshooting/frequently-asked-questions/standards-v-drift.md "mention"). To learn more about what you can do with drift, see [drift.md](../manage/drift.md "mention").
{% endhint %}

## Actions

Each standard in a template is set to one or more of the following.

| Action    | Description                                                                                                                                                                   |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Report    | Logs the current configuration and stores it in the CIPP database for your standards reports or BPA reports.                                                                  |
| Alert     | Sends a notification via the method configured under CIPP, Application Settings, Notifications.                                                                               |
| Remediate | Changes the tenant's configuration, and reports in the backend. All Remediate standards also Report, so enabling Report alongside it is optional and only for visual clarity. |

Take the Audit Log standard as an example. Set to **Report** across an All Tenants template, it fills the CIPP database with each tenant's current setting without changing anything. Set to **Alert**, it also notifies you through your email or ticketing system. Set to **Remediate**, it enables the audit log wherever it is off.

{% hint style="info" %}
A small number of standards do not offer all three actions. Template-deployment standards, such as transport rule and Exchange connector templates, are Remediate only, because there is no existing configuration to report on. A few others are Report and Alert only where CIPP cannot safely make the change itself. Where an action is unavailable, it will not be offered when you configure the standard.
{% endhint %}

## Precedence of Standards

Standards templates are merged, so a tenant can be covered by several at once. Where two templates configure the same setting differently, the winner is decided first by specificity, then by which was most recently saved.

### Specificity

A more specific template always overrides a more general one. If an All Tenants template enables external warnings but one client needs it disabled, applying a tenant-specific template disables it for that client alone.

| Priority | Scope             | Overrides                    |
| -------- | ----------------- | ---------------------------- |
| Highest  | Individual tenant | Tenant group and All Tenants |
| Middle   | Tenant group      | All Tenants                  |
| Lowest   | All Tenants       | Nothing                      |

### Most Recently Saved

When two templates conflict at the same level of specificity, the one saved most recently wins.

{% hint style="warning" %}
This is based on when a template was last saved, not when it was created. Editing an older template moves it to the front of the queue, so it can start overriding a newer template that previously took precedence. If a setting stops behaving as expected after an unrelated edit, this is the first thing to check.
{% endhint %}

## Standards Categories

Standards are grouped into the following categories, which match the Category label on the standard selection page.

| Category                    | Description                                                                                          |
| --------------------------- | ---------------------------------------------------------------------------------------------------- |
| Global Standards            | Organization-wide configuration applied across the tenant.                                           |
| Entra (AAD) Standards       | Identity configuration, including authentication methods and Conditional Access.                     |
| Exchange Standards          | Email settings such as spam protection, mailbox configuration, and message handling.                 |
| Defender Standards          | Protection against phishing, malware, and other threats.                                             |
| Intune Standards            | Device and application management policies.                                                          |
| Device Management Standards | Device enrolment and lifecycle configuration.                                                        |
| SharePoint Standards        | SharePoint and OneDrive configuration, including sharing and retention.                              |
| Teams Standards             | Collaboration settings such as meeting policies and external file sharing.                           |
| Copilot (M365) Standards    | Microsoft 365 Copilot availability and configuration.                                                |
| Templates                   | Deploys a saved template, such as a transport rule, Exchange connector, group, or assignment filter. |

## Impact Levels

Each standard is labelled with the level of change it introduces and its effect on users.

| Impact | Description                                                                                     |
| ------ | ----------------------------------------------------------------------------------------------- |
| Low    | Minimal or no user-facing effects.                                                              |
| Medium | May require some communication with users to prepare them for changes.                          |
| High   | Significant changes that could affect daily workflows. Coordinate with clients before applying. |

{% hint style="warning" %}
#### Important Considerations

* **Nothing runs until you set it up.** Standards are not applied to any tenant when CIPP is installed. You must create and apply templates yourself. Apply them with a clear understanding of their effects.
* **Companion policies.** Some standards rely on additional policies in tools such as Microsoft Intune to be fully effective. Ensure any required companion policies are in place.
* **Deselecting a standard does not undo it.** Removing a standard stops it being enforced in future cycles, but leaves the current configuration alone. Deselecting `Enable FIDO2 capabilities` stops CIPP enforcing it, but FIDO2 stays enabled where it was already turned on.
* **Application cadence.** Standards reapply every twelve hours. A setting changed outside the standard will be overridden at the next cycle. Drift templates are evaluated on the same twelve hour cadence, shortly after the standards run.
* **License-aware skipping.** If a tenant is not licensed for a setting in a template, for example a Conditional Access standard applied to a tenant without Entra P1, that standard is skipped rather than failed. This is reflected in the **License Missing Percentage** and **Combined Alignment Score** columns on the Standards & Drift Alignment page, and means it is safe to apply a mixed-license template across tenants.
{% endhint %}

{% hint style="info" %}
Plans exist to implement more standardized options and settings. If there is a standard you want, see the Feature Requests section below.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

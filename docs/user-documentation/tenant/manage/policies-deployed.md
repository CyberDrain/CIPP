# Policies and Settings Deployed

{% hint style="info" %}
This page is hidden while the **Baselines** feature flag is on in [features.md](../../cipp/settings/features.md "mention"), because [README.md](../baselines/README.md "mention") replace Standards and Drift.
{% endhint %}

This page shows what a single standards template contains and how each item currently stands against the selected tenant. It is a read-only view built by comparing the template's contents with the tenant's live configuration, broken into Security Standards, Intune Policies and Conditional Access Policies.

Two things determine what is shown: the template chosen in the **Template** picker at the top of the page, and the tenant currently selected in CIPP. Each section header carries a count of the items in it, and sections can be collapsed.

{% hint style="info" %}
Until a template is selected, all three sections are empty. Arriving from a standards template carries the selection through, otherwise choose one from the **Template** picker.
{% endhint %}

## Page Actions

| Action           | Description                                                                                                                                                                    |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Refresh Data     | Re-reads the template, the comparison against the tenant, and the recorded deviations.                                                                                         |
| Edit Template    | Opens the standards template for editing.                                                                                                                                      |
| Run Standard Now | Forces a run of the template outside its normal schedule. You choose which tenant to run against from the tenants the template applies to, with any excluded tenants left out. |

## Status Values

The Status column in each section describes how the item stands against the tenant at the time of the last comparison.

| Status                | Description                                                                                                                                            |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Deployed              | The tenant matches the template, either because the comparison reports the item as compliant or because the expected and current values are identical. |
| Not Deployed          | The comparison reports the item as not applied to the tenant.                                                                                          |
| Deviation - New       | A difference has been found that has not yet been reviewed.                                                                                            |
| Deviation - \<status> | A difference recorded against the tenant, shown with its current review status. Deviations are reviewed on drift.md.                                   |
| Not Configured        | No comparison data exists for the item, usually because the template has not yet run against this tenant.                                              |

## Security Standards

Every item in the template other than Intune and Conditional Access templates.

| Column        | Description                                                                                  |
| ------------- | -------------------------------------------------------------------------------------------- |
| Name          | The standard's display name, taken from the standards list.                                  |
| Category      | Always Security Standard in this section.                                                    |
| Status        | How the standard stands against the tenant. See Status Values above.                         |
| Last Modified | The date the comparison data for this standard was last refreshed, or N/A where none exists. |

## Intune Policies

The Intune templates included in the standards template. A template brought in through a tag has the tag's name appended to it, shown as the template name followed by the tag in brackets.

| Column          | Description                                                                                                 |
| --------------- | ----------------------------------------------------------------------------------------------------------- |
| Name            | The Intune template's display name. Where the template came from a tag, the tag name is shown alongside it. |
| Category        | Always Intune Template in this section.                                                                     |
| Platform        | Always Multi-Platform in this section.                                                                      |
| Status          | How the template stands against the tenant. See Status Values above.                                        |
| Last Modified   | The date the comparison data for this template was last refreshed, or N/A where none exists.                |
| Assigned Groups | The assignment configured on the template in the standard, or N/A where none is set.                        |

## Conditional Access Policies

The Conditional Access templates included in the standards template, with the same tag handling as Intune templates.

| Column        | Description                                                                                                                     |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Name          | The Conditional Access template's display name. Where the template came from a tag, the tag name is shown alongside it.         |
| State         | The state configured on the template, for example enabled or report-only. Shows Unknown where the template does not record one. |
| Status        | How the template stands against the tenant. See Status Values above.                                                            |
| Conditions    | Always Conditional Access Policy in this section.                                                                               |
| Controls      | Always Access Control in this section.                                                                                          |
| Last Modified | The date the comparison data for this template was last refreshed, or N/A where none exists.                                    |

{% include "../../../../.gitbook/includes/feature-request.md" %}

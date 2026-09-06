---
description: Manage scheduled tenant alerts.
---

# Add Alert

CIPP offers a set of alert checks that run against your tenants and notify you through your configured channels. Some duplicate Microsoft Alerts functionality in a more MSP-friendly manner, and some are not available as a Microsoft Alert at all. Similar to standards, you choose the alert type, select one or more tenants or tenant groups, configure the criteria, then decide how you want to be notified.

{% hint style="info" %}
This same page is used for the Edit Alert and Clone & Edit Alert actions, with the selected alert's configuration loaded in for you to review, alter and save.
{% endhint %}

## Alert Types

Within CIPP, there are two types of alerts. Choose one of the two cards at the top of the page to reveal the matching form.

* **Audit Log Alert** - Creates an alert based on a received Microsoft audit log entry.
* **Scripted CIPP Alert** - Creates an alert based on data processed by CIPP, pulling from sources other than the audit logs.

## Alert Timing

* **Audit Log Alerts** - Processed in near real-time, but a small delay of up to 15 minutes is normal.
* **Scripted CIPP Alerts** - Each alert comes with a default recurrence suggested by the CIPP team, which you can adjust as needed. The available recurrences are every 30 minutes, hour, 4 hours, day, 7 days, 14 days, 21 days, 30 days or 365 days.

## Tenant Selector

Both alert types share the same tenant scoping card.

| Field                      | Description                                                                                         |
| -------------------------- | --------------------------------------------------------------------------------------------------- |
| Included Tenants for alert | The tenants, tenant groups or \*All Tenants the alert applies to. At least one entry is required.   |
| Excluded Tenants for alert | Optional. Tenants selected here are skipped even if they fall within the included tenants or group. |

{% hint style="info" %}
Tenant group membership is resolved each time the alert runs, for both alert types. A tenant added to or removed from a targeted group is picked up automatically, with no need to edit and re-save the alert.
{% endhint %}

## Alert Criteria

The criteria card changes depending on which alert type you selected.

### Audit Log Alert

| Field                                         | Description                                                                                                                                                               |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Select an alert preset, or customize your own | Loads a ready-made set of conditions for a common scenario. Once loaded, the conditions can still be edited, or you can skip the preset and build the alert from scratch. |
| Select the log source                         | The audit log the alert watches, either Azure AD or Exchange. This determines which properties are offered in the condition builder. Required.                            |

Use **Add a condition** to build the rule. Each condition is a property, an operator and an input value, and multiple conditions are combined, so the alert only triggers when all of them match. The delete icon at the end of a row removes that condition.

| Field           | Description                                                                                                                                                                                  |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Select property | The audit log property to test. The list is driven by the chosen log source. You can also type a property that is not in the list to create a custom one, which is treated as a text value.  |
| is              | The comparison to apply: `Equals to`, `Not Equals to`, `Like`, `Not like`, `Does not match`, `Greater than`, `Less than`, `In`, or `Not In`.                                                 |
| Input           | The value to compare against. This is a free-text box for most properties, a picker when the property has a known set of values, and a multi-value picker when the operator is In or Not In. |

### Scripted CIPP Alert

| Field                            | Description                                                                                                            |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| What alerting script should run  | The CIPP alert check to run. See [#available-alerts](alert.md#available-alerts "mention") for the full list. Required. |
| When should the alert run        | How often the check repeats. Required.                                                                                 |
| When should the first alert run? | The date and time of the first run, with the recurrence counted from there.                                            |

Some alert scripts need extra information, such as a threshold value or a list of items to watch. Any additional fields appear beneath the recurrence options once you have selected the script and are labelled by the script itself.

## Notification Settings

### Actions to take

Required for both alert types, and the available options differ.

For a **Scripted CIPP Alert**, this is how the alert is delivered:

* Webhook - Delivers a JSON payload to the webhook configured in [notifications.md](../../../cipp/settings/notifications.md "mention").
* PSA - Delivers a formatted payload to the PSA configured in [notifications.md](../../../cipp/settings/notifications.md "mention").
* Email - Delivers an HTML-formatted table to the email address provided in [notifications.md](../../../cipp/settings/notifications.md "mention").

For an **Audit Log Alert**, this is what CIPP does when a matching log entry arrives, and it can include remediation as well as notification:

* Execute a BEC Remediate - Runs the business email compromise remediation against the user in the log entry.
* Disable the user in the log entry - Immediately disables the account named in the matching log entry.
* Generate an email - Sends an email notification.
* Generate a PSA ticket - Raises a ticket in the configured PSA.
* Generate a webhook - Sends the alert to the configured webhook.

{% hint style="warning" %}
Execute a BEC Remediate and Disable the user in the log entry act on the tenant without further confirmation. Test the conditions on a narrow scope before applying them broadly.
{% endhint %}

### PSA Ticket Strategy

Shown for scripted alerts when PSA is one of the selected actions. It overrides the HaloPSA Link Tickets to affected Users toggle for this alert only, which is handy for wide alerts such as users without MFA where you want to control how many tickets are raised.

| Option                             | Description                                                   |
| ---------------------------------- | ------------------------------------------------------------- |
| One ticket per affected user       | Raises a separate ticket for each user returned by the alert. |
| One consolidated ticket per tenant | Raises a single ticket per tenant listing every result.       |

Whichever option matches your current HaloPSA integration setting is labelled as the integration default.

### PSA Ticket Priority

Shown for both alert types when Generate a PSA ticket (or PSA) is one of the selected actions, and only while the HaloPSA integration is enabled. Overrides the HaloPSA Default Priority for tickets raised by this alert, restricted to the priorities available on the integration's Ticket Type. Leave it blank to use the integration default.

{% hint style="info" %}
The dropdown is shown disabled with an explanation instead of a priority list when there is nothing valid to offer: no Ticket Type is set on the integration yet, the configured Ticket Type has no SLA attached (so HaloPSA is left to apply its own priority regardless of any selection here), or the priority list could not be loaded.
{% endhint %}

### Custom Subject

Overrides the default notification subject with your own text. The value is prefixed with the tenant default domain name for easier filtering, giving `$TenantDomain - $CustomSubject`. Leave it blank to use the default subject format.

### Alert Comment

Free-text information to carry with the alert, such as documentation links, FAQ references or instructions for whoever picks it up. Variable replacement is supported, including `%tenantfilter%`, `%tenantname%`, `%resultcount%` for the number of results that triggered the alert, and any custom variables you have defined.

Once the criteria and notification settings are complete, **Save Alert** on the Notification Settings card writes the alert. The button stays disabled until every required field is valid.

## Setting Up an Audit Log Alert

{% @storylane/embed subdomain="app" url="https://app.storylane.io/share/6wxwpjesdsrx" linkValue="6wxwpjesdsrx" %}

## Setting Up A CIPP Scripted Alert

{% @storylane/embed subdomain="app" url="https://app.storylane.io/share/9r1i7cklndrq" linkValue="9r1i7cklndrq" %}

## Available Alerts

You can review the available alerts embedded below or navigate to [https://resources.cipp.app/?tab=alerts](https://resources.cipp.app/?tab=alerts).

{% hint style="info" %}
The **Alert on Huntress or CIPP Rogue Apps detected** alert checks tenants against both the public Huntress RogueApps feed and a list curated by CIPP, so it can report applications that do not appear on the Huntress website. See [rogue-apps.md](rogue-apps.md "mention") for how the list is built and which applications the CIPP list contains.
{% endhint %}

{% hint style="warning" %}
The **Alert on OneDrive accounts with over-long paths** alert reads from a cache that CIPP does not refresh on a schedule, unlike most alert data. Run **Refresh CIPPDB Cache** for the **OneDrive Long Paths** cache type on the tenant from [tenants.md](../../../cipp/settings/tenants.md "mention") before relying on this alert, and again whenever you want it to reflect current data. It stores each affected user's UPN and a count of long paths only, never file or folder names.
{% endhint %}

{% @cipp-external-webpage-block/cyberdrain url="https://resources.cipp.app/?tab=alerts" fullWidth="true" %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

# Add Standards Template

When creating a template, it is worth thinking about how you want your standards organized first. CyberDrain recommends splitting templates per category or service level. This stops a template growing so large it becomes impossible to manage. Splitting by area such as Intune Templates, Entra Settings, or Managed Devices works well.

The same page builds both Standards templates and Drift templates. Which one you get depends on how you arrived: **Add Template** opens it in standards mode, **Create Drift Template** opens it in drift mode. The layout is shared, but a few options differ, and those differences are called out below.

## Creating a Standards Template

{% stepper %}
{% step %}
### Set a Name for the Template

In the **Template Name** field, enter the name for this template.
{% endstep %}

{% step %}
### Assign Template to Tenants

In the **Included Tenants** dropdown, select the tenant or tenants this template should apply to. You can also select a tenant group.

{% hint style="info" %}
If you select AllTenants, an **Excluded Tenants** dropdown appears, so you can name any tenants or tenant groups this template should skip.
{% endhint %}

{% hint style="warning" %}
Below the tenant selection is a **Do not run on schedule** toggle. Turn this on and the template runs only when you trigger it by hand. Leave it off for the template to run every twelve hours.
{% endhint %}
{% endstep %}

{% step %}
### Add Standards to the Template

Click **Add Standard to Template** at the top of the page. This opens a dialog listing every standard you can configure, with search and filtering described under [#finding-standards](template.md#finding-standards "mention").

Turn on **Add this standard to the template** for each standard you want, then close the dialog.

{% hint style="warning" %}
Standards marked **Deprecated** cannot be added. Where one exists, the dialog points you at the replacement.
{% endhint %}
{% endstep %}

{% step %}
### Configure Each Standard

For each standard you added:

* Set the desired action or actions. For help choosing, see #actions. To apply the same actions across the whole template at once, use **Set All Actions** in the toolbar above the list, tick the actions you want, and choose **Apply to all standards**. This replaces each standard's current selection, and any action a standard does not support is skipped for that standard.
* Most standards have additional fields to complete. Review and set these as needed.
* Click Save to store the settings for that standard, or Cancel to discard your changes.

The toolbar above the list has **All**, **Configured**, and **Unconfigured** buttons with live counts, which is the quickest way to find what you have not finished yet.

{% hint style="info" %}
**Fuzzy Match Distance** (available on some standards) sets how closely a policy name must match before it is treated as the same policy. The value is the Levenshtein distance, which is the number of single-character changes needed to turn one name into another. 0 requires an exact match, 1 tolerates a single character difference, 2 tolerates two, and so on. Higher values match more loosely but risk matching unrelated policies.
{% endhint %}
{% endstep %}

{% step %}
### Save the Template

Once every standard shows as configured, click **Save Template** at the top of the page. It stays disabled until the template is complete.
{% endstep %}
{% endstepper %}

## Creating a Drift Template

Drift templates monitor tenant configuration continuously and report what has changed, rather than silently correcting it. A drift template with automatic remediation enabled on a setting behaves as a superset of a classic Remediate standard for that setting, so you generally do not need to maintain parallel classic and drift templates carrying the same payloads.

{% hint style="danger" %}
#### One Drift Template per Tenant

Each tenant can have only a single drift template applied. Adding a tenant that already belongs to another drift template returns an error.
{% endhint %}

### Remediation Options

Drift standards are set to **Report** by default. Enabling automatic remediation on a standard changes it to **Report and Remediate**.

| Option                | Behavior                                                                        |
| --------------------- | -------------------------------------------------------------------------------- |
| Automatic Remediation | Reverts the change back to the template configuration as soon as it is detected. |
| Manual Remediation    | Raises the deviation for review, so you can accept or deny it yourself.          |

{% hint style="info" %}
Drift alerting is configured on the template itself, through the Drift Alert Webhook and Drift Alert Email fields, rather than by setting an Alert action on individual standards.
{% endhint %}

### Key Features

* Monitors security standards, Conditional Access policies, and Intune policies
* Detects changes made outside CIPP
* Configurable webhook and email notifications
* Granular control over deviation acceptance

### Building the Template

{% stepper %}
{% step %}
### Set a Name for the Template

In the **Template Name** field, enter the name for this template.
{% endstep %}

{% step %}
### Assign Template to Tenants

In the **Included Tenants** dropdown, select the tenant or tenants this template should apply to. You can also select a tenant group.

{% hint style="info" %}
If you select AllTenants, an **Excluded Tenants** dropdown appears, so you can name any tenants or tenant groups this template should skip.
{% endhint %}

Drift templates always run on the schedule, so the Do not run on schedule toggle is not offered here.
{% endstep %}

{% step %}
### Optionally Set Notification Settings

| Field                     | Description                                                                                |
| ------------------------- | ------------------------------------------------------------------------------------------ |
| Drift Alert Webhook       | A webhook URL for drift alerts. Leave blank to use the default webhook.                    |
| Drift Alert Email         | An email address for drift alerts. Leave blank to use the default address.                 |
| Disable All Notifications | Turns off notifications for this template, so drift is only visible when you check for it. |

Defaults come from [notifications.md](../../cipp/settings/notifications.md "mention").
{% endstep %}

{% step %}
### Add Standards to the Template

Click **Add Standard to Template** and turn on **Add this standard to the template** for each standard you want, then close the dialog. Search and filtering work the same as for standards templates.
{% endstep %}

{% step %}
### Configure Each Standard

For each standard, set the automatic remediation toggle if you want the change reverted rather than reported, complete any additional fields, and click Save.

{% hint style="info" %}
**Set All Actions** is not available on drift templates, since drift standards do not take a free choice of actions.
{% endhint %}
{% endstep %}

{% step %}
### Save the Template

Once every standard shows as configured, click **Save Template** at the top of the page. The template is evaluated every twelve hours from then on.
{% endstep %}
{% endstepper %}

## Finding Standards

The Add Standard to Template dialog can list a lot of standards, so it offers a search box and a set of filters. **Search Standards** matches on a standard's name, description, or tags. Expanding **View, Sort & Filter Options** gives you the rest.

| Option                   | Description                                                                                  |
| ------------------------ | -------------------------------------------------------------------------------------------- |
| View                     | Switches between Card and List presentation.                                                 |
| Sort By                  | Sorts by Name or Date Added.                                                                 |
| Order                    | Ascending or Descending, applied to the Sort By selection.                                   |
| Categories               | Restricts the list to the chosen standards categories.                                       |
| Impact                   | Restricts the list to the chosen impact levels.                                              |
| Recommended By           | Restricts the list to standards recommended by the chosen organizations.                     |
| Compliance Tags          | Restricts the list to standards mapped to the chosen compliance frameworks.                  |
| New (30 days)            | Shows only standards added to CIPP in the last thirty days, for picking up recent additions. |
| All / Enabled / Disabled | Shows all standards, only those already added to this template, or only those not yet added. |

A **Clear** button appears once any filter is active.

## See It In Action

{% @storylane/embed subdomain="app" url="https://app.storylane.io/share/gykd6vk1y7kr" linkValue="gykd6vk1y7kr" %}

{% hint style="info" %}
To see how Custom Variables and Tenant Groups can be combined to graduate tenants through standards, see [#using-custom-variables-to-manage-standards-templates](../../../demos/tutorials.md#using-custom-variables-to-manage-standards-templates "mention").
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

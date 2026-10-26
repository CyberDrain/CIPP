# Edit Assignment Filter Template

Opens a saved assignment filter template so its values can be changed. Edits are stored against the template in CIPP, so they take effect the next time the template is deployed rather than changing any filter already created in a tenant.

The form is the same as [add.md](add.md "mention"), populated with the template's stored values.

| Field        | Description                                                                           |
| ------------ | ------------------------------------------------------------------------------------- |
| Display Name | The name of the filter the template creates. Required.                                |
| Description  | The description recorded against the filter.                                          |
| Filter Type  | Whether the filter matches Devices or Apps.                                           |
| Platform     | The platform the filter applies to.                                                   |
| Filter Rule  | The rule deciding what the filter matches, written in Intune filter syntax. Required. |

{% hint style="info" %}
Unlike an assignment filter itself, a template's Filter Type and Platform can be changed after it has been created, since nothing exists in a tenant until the template is deployed.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

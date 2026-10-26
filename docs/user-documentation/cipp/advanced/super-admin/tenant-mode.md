# Tenant Mode

Super admins should use this page to determine which mode CIPP operates in.

{% hint style="danger" %}
For further information on the limitations of each mode, please review [owntenant.md](../../../../setup/installation/owntenant.md "mention").
{% endhint %}

| Mode                              | Description                                                                                                                                                                                                                                                                                                                                        |
| --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Multi Tenant - GDAP Mode          | This is the default CIPP mode. This presents you with your client tenants only.                                                                                                                                                                                                                                                                    |
| Multi Tenant - Add Partner Tenant | Optionally enabled, this mode will allow you to manage your partner tenant through CIPP in addition to your client tenants. It is recommended that if you are going to enable this mode that you review the [#limitations-of-partner-tenant-enabled](../../../../setup/installation/owntenant.md#limitations-of-partner-tenant-enabled "mention"). |
| Single Tenant - Own Tenant Mode   | Optionally enabled, this mode manages the tenant CIPP is deployed in without GDAP. Other tenants can still be added as direct tenants. It is recommended that if you are going to enable this mode that you review the [#limitations-of-single-tenant-mode](../../../../setup/installation/owntenant.md#limitations-of-single-tenant-mode "mention").                                               |

{% hint style="warning" %}
After changing the tenant mode, clear your tenant cache by clicking Force Refresh on the [tenants.md](../../settings/tenants.md "mention") settings page.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

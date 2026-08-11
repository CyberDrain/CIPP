---
description: Configuring the Gradient Extension
---

# Gradient

The Gradient integration sends Microsoft 365 license counts from CIPP to Gradient for billing reconciliation, and can raise alerts in Gradient where your PSA supports ticket creation through it. Accounts and services are created in Gradient automatically from your tenants and their licenses, and are then matched to your Synthesize records in Gradient's own interface.

{% hint style="info" %}
Gradient maintain their own version of this guide, which will usually be more current on the Synthesize side of the setup. See [Gradient's CIPP documentation](https://support.meetgradient.com/cipp).
{% endhint %}

## Settings

| Setting                                            | Description                                                                                                                                    |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| Enable Integration                                 | Turns the integration on. The remaining settings and the **Test** and **Force Sync** buttons stay unavailable until this is enabled and saved. |
| Gradient Vendor API Key                            | The vendor key generated against your custom integration in Synthesize.                                                                        |
| Gradient Partner API Key                           | The partner key generated alongside it. Stored securely and masked once saved; leave blank on later saves to keep the existing value.          |
| Enable sending all license information to Gradient | Allows CIPP to push license counts to Gradient. Without this, no synchronisation takes place, whether scheduled or triggered manually.         |

{% hint style="warning" %}
**Force Sync** only queues a synchronisation when **Enable sending all license information to Gradient** is also on. With the integration enabled but that setting off, the button appears active but nothing is queued.
{% endhint %}

Gradient does not use CIPP's **Tenant Mapping** tab. Tenants are published to Gradient as accounts automatically, and matching them to your Synthesize records happens in Gradient's interface rather than in CIPP.

## Setting Up the Integration

{% stepper %}
{% step %}
### Generate vendor API keys in Synthesize

Sign in to [Synthesize](https://app.usegradient.com/login), go to **Integrations** and select **Custom**. Choose the modules you want to integrate, name the integration something recognisable such as _CyberDrain_ or _CIPP_, accept the terms and conditions, and generate the API keys. Record both keys before leaving the page.
{% endstep %}

{% step %}
### Connect the integration in CIPP

Turn on **Enable Integration**, then enter the **Gradient Vendor API Key** and **Gradient Partner API Key**. Turn on **Enable sending all license information to Gradient** if you want license counts synchronised, then select **Submit**.
{% endstep %}

{% step %}
### Test the connection

Select **Test**. A green banner confirms the keys are correct. This also marks the integration as active on the Gradient side, so it is worth doing before returning to Synthesize.
{% endstep %}

{% step %}
### Run the first sync

Select **Force Sync**. This publishes your tenants to Gradient as accounts and creates a service for each license in use, giving Synthesize something to map against.
{% endstep %}

{% step %}
### Map accounts and services in Synthesize

Return to Synthesize and select the status refresh button for the CIPP integration, then select **Next** to begin mapping.

Map your accounts by dragging each card from Synthesize on the left onto the matching CIPP entry on the right. Exact matches are mapped for you; the rest can be found using the filter button or the Synthesize search bar. Select **Next** when finished.

Map your services the same way, then select **Next**, review, and select **Finish**.
{% endstep %}

{% step %}
### Import usage

Back in CIPP, select **Force Sync** once more to import usage against the newly mapped services.
{% endstep %}
{% endstepper %}

## How Synchronisation Works

Each run publishes any tenant that does not already exist in Gradient as an account, using the tenant's display name and default domain name. The default domain name is the account identifier, so it is also what ties alerts to the right Gradient account.

For every license held by a tenant, CIPP looks for a matching service in Gradient by the license's friendly product name. Where none exists, a service is created automatically under the _infrastructure_ category and _hosted email_ subcategory, which you can adjust in Synthesize afterwards. The count reported against each service is the number of licenses purchased rather than the number assigned.

Synchronisation runs automatically once a day, and can be triggered at any time with **Force Sync**. Both routes require **Enable sending all license information to Gradient** to be on.

{% hint style="info" %}
Licenses excluded globally in CIPP's license settings are left out of the counts sent to Gradient. Exclusions that apply only to alerting are still included, so a license hidden from alerts will continue to be billed.
{% endhint %}

## Alerting and Ticket Creation

When Gradient is enabled, CIPP alerts configured to deliver to a PSA are also sent to Gradient, which can raise a ticket where your PSA supports it. Alerts are addressed to the Gradient account matching the tenant's default domain name, and the account is created first if it does not yet exist.

CIPP checks the delivery status of each alert after sending it, and records a failure in the CIPP logs where Gradient reports that the alert could not be delivered. If tickets are not appearing, the logs are the first place to look.

{% include "../../../../.gitbook/includes/feature-request.md" %}

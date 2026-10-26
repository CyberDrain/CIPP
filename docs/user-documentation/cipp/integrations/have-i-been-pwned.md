# Have I Been Pwned?

The Have I Been Pwned integration lets CIPP check tenant domains and individual accounts against the Have I Been Pwned breach database, surfacing compromised credentials found in public breaches and dark web dumps. Results are available on demand through the breach lookup tools, and can be raised automatically as alerts.

## Settings

| Setting                                                                                      | Description                                                                                                                                                                                                |
| -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enter your own HIBP API Key. When you are a CyberDrain hosted partner, leave this key blank. | Your Have I Been Pwned API key. Stored securely and masked once saved. CyberDrain-hosted subscribers can leave this blank to fall back to the shared key provided through CyberDrain's partnership with HIBP. |
| Enable Integration - Allow darkweb scanning through tools and alerts                         | Turns the integration on. The API key field and the **Test** button remain unavailable until this is enabled and saved.                                                                                    |

{% hint style="info" %}
The API key field appears above the toggle on screen, but the toggle governs it. Enable the integration first, then the key field becomes editable.
{% endhint %}

## Setting Up the Integration

{% stepper %}
{% step %}
### Obtain an API key

Purchase or retrieve an [API key from HIBP](https://haveibeenpwned.com/API/Key).

CyberDrain-hosted subscribers have access to a complimentary key through a partnership with HIBP and can skip this step, leaving the key blank.
{% endstep %}

{% step %}
### Enable the integration

Turn on **Enable Integration - Allow darkweb scanning through tools and alerts**.
{% endstep %}

{% step %}
### Enter your key

Paste your HIBP key into the key field. Leave it blank if you are relying on the CyberDrain-hosted complimentary key.
{% endstep %}

{% step %}
### Save and test

Select **Submit**, then select **Test**. The test queries your HIBP subscription status, so a successful result confirms both that the key is valid and that the subscription behind it is active. Any failure is reported with the underlying error.
{% endstep %}
{% endstepper %}

## Clearing the API Key

A **Clear API Key** button removes the stored key entirely. This is mainly useful when moving from self-hosted to CyberDrain-hosted, where clearing your own key allows the complimentary shared key to take over.

{% hint style="warning" %}
The button clears the key immediately, without a confirmation prompt. It also remains available whether or not the integration is enabled.
{% endhint %}

## Where Breach Data Is Used

Breach data reaches CIPP in two ways, on demand from the lookup pages and on a schedule from the breach alert, which is worth knowing when troubleshooting.

| Feature              | Description                                                                                                                                                                 |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant Breach Lookup | Runs a breach search across every domain in the selected tenant and stores the results for later viewing.                                                                   |
| Breach Lookup        | Checks a single email address or domain on demand.                                                                                                                          |
| Breach alert         | The **Alert on (new) potentially breached passwords** alert runs a tenant breach search on its schedule and raises an alert when new breaches are found since the last run. |

{% hint style="info" %}
A tenant breach search runs as a background job and can take up to 24 hours to complete, so the confirmation message means the search has been queued rather than finished. Results appear on the Tenant Breach Lookup page once available.
{% endhint %}

{% hint style="warning" %}
Have I Been Pwned rate-limits API requests according to your subscription tier. Where a lookup is rate-limited, CIPP reports this rather than failing outright, and the request needs retrying after the wait period. Accounts with no breach history return no results rather than an error, so an empty result is a genuine answer.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

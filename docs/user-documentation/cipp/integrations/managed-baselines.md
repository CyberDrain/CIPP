# CyberDrain Managed Baselines

{% hint style="warning" %}
**Coming soon.** Managed Baselines is not open for subscriptions yet. The **Managed** tab and the integration already appear in CIPP, but you cannot get an API key or use the service until it launches.
{% endhint %}

The CyberDrain Managed Baselines integration connects CIPP to CyberDrain's managed baseline service. With it enabled, the [Managed](../../tenant/baselines/managed.md) tab under Baselines lists the baselines CyberDrain publishes and lets you request a custom baseline built for your MSP.

{% hint style="info" %}
Managed Baselines is a paid CyberDrain service and needs an API key from your subscription. The integration is optional: community baselines and everything else in CIPP work without it. CIPP only contacts the service while the integration is enabled.
{% endhint %}

## Settings

| Setting                   | Description                                                                                                                                  |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Enable Integration        | Turns the integration on. The key field and the **Test** button remain unavailable until this is enabled and saved.                           |
| Managed Baselines API Key | The API key from your Managed Baselines subscription. Stored securely and masked once saved. Leave it blank to keep the key you saved before. |

## Configuring the Integration

{% stepper %}
{% step %}
### Enable the integration

Open **CIPP** > **Integrations**, select **CyberDrain Managed Baselines**, turn on **Enable Integration** and save.
{% endstep %}

{% step %}
### Enter your key

Enter the API key from your Managed Baselines subscription and save again.
{% endstep %}

{% step %}
### Test the connection

Use the **Test** button. A successful test names the partner the key belongs to. A rejected key is reported as such.
{% endstep %}
{% endstepper %}

## What Happens When It Is Turned Off

Baselines you added or had built stay in CIPP as ordinary baselines and keep running exactly as before. The **Align** and **Merge** actions are no longer offered, the Managed tab goes back to explaining the service, and CIPP stops contacting CyberDrain. Nothing is removed from any tenant.

{% include "../../../../.gitbook/includes/feature-request.md" %}

# Automated Onboarding

The Automated Onboarding page subscribes CIPP to Microsoft Partner Center webhooks, so that tenants are onboarded automatically as relationships are created and CIPP is alerted to partner-level events. Saving the settings replaces any existing webhook subscription with one pointing at your CIPP instance. Microsoft's [Partner Center webhook documentation](https://learn.microsoft.com/partner-center/developer/partner-center-webhooks) describes the individual event types in detail.

## Subscription Status

The panel at the top of the page reports the state of the current subscription.

| Field        | Description                                                                                                                                                    |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Status       | Whether automated onboarding is currently Enabled or Disabled.                                                                                                 |
| Webhook URL  | The address Partner Center is currently configured to send events to. A warning appears here if this does not match the address your instance is published on. |
| Last Updated | When the subscription was last changed.                                                                                                                        |

{% hint style="warning" %}
**If you have migrated to a new CIPP instance, check the Webhook URL.**

The subscription held in Partner Center records the exact address CIPP was reachable at when it was created. Migrating CIPP, including migrating to the container-based next-generation release, changes that address, but the subscription in Partner Center does not follow it. Partner Center carries on delivering events to the old address, so tenants silently stop being onboarded and partner alerts stop arriving, with nothing on this page failing outright.

CIPP compares the registered address against the one your instance is published on and shows a warning beneath the Webhook URL when they differ, naming the address it expects. To correct it, save the settings on this page: this re-registers the subscription against that address. This is worth checking as a matter of course after any migration or change of hostname, and if automated onboarding was working before a migration and has since gone quiet.
{% endhint %}

The address CIPP expects is the custom domain bound to your instance, not the address you happen to be browsing on, so opening this page over the default `*.azurewebsites.net` hostname does not change what it asks you to register. If several custom domains are bound, CIPP uses the first one for webhooks and for the links in its notification emails, and says which one that is beneath the Webhook URL.

That address is re-checked every time CIPP starts. If the instance's stored URL has drifted it is corrected, and **if automated onboarding is enabled the Partner Center subscription is re-registered against the correct address as well**, so binding a new custom domain normally repairs itself without anything being done on this page. The re-registration keeps your selected event types.

Startup will not re-register in two cases, both deliberate. If CIPP cannot confirm the bound hostname with Azure, which includes any deployment not running on App Service, it leaves the subscription alone rather than guessing, because guessing wrong would point Partner Center at an address CIPP is not served on. And if Partner Center cannot be reached, it makes no change at all. In either case the warning on this page and a manual save remain the fix.

## Settings

| Setting                                            | Description                                                                                                                                                                                                         |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enable Automated Onboarding                        | Turns the Partner Center webhook subscription on or off.                                                                                                                                                            |
| Event Types                                        | The Partner Center events CIPP subscribes to. The list is retrieved from Partner Center, and several can be selected.                                                                                               |
| Exclude onboarded tenants from top-level standards | When enabled, tenants onboarded automatically by this process are excluded from standards applied at the All Tenants level, so that a newly onboarded tenant does not immediately receive your top-level standards. |

## Easy Mode to Set Up

{% stepper %}
{% step %}
#### Enable automated onboarding

Turn on **Enable Automated Onboarding**.
{% endstep %}

{% step %}
#### Choose your event types

Select the Partner Center events CIPP should receive under **Event Types**. Tenant relationship events are what drive automatic onboarding; the remaining types are for partner-level alerting.

{% hint style="info" %}
You do not need to select any event types for this to work. Simply saving will automatically pull in `test-created` and `granular-admin-relationship-approved` needed for automatic onboarding to work.
{% endhint %}
{% endstep %}

{% step %}
#### Decide how new tenants are treated

If you would rather newly onboarded tenants were not picked up by your All Tenants standards straight away, turn on **Exclude onboarded tenants from top-level standards**.
{% endstep %}

{% step %}
#### Save

Save the page. This creates the subscription in Partner Center, replacing any existing one, and points it at your current CIPP address.
{% endstep %}

{% step %}
#### Test the webhook

Select **Test Webhook** and confirm the result, as described below. A response code of 200 means Partner Center reached CIPP successfully.
{% endstep %}
{% endstepper %}

## Testing the Webhook

The **Test Webhook** button asks Partner Center to deliver a test event and reports what happened. The results panel updates as the test progresses and can be dismissed once you are finished with it.

| Field            | Description                                                                                                                         |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Response Code    | The HTTP status Partner Center received from CIPP. 200 indicates success; anything else indicates the event could not be delivered. |
| Status           | The state of the test, which moves from submitted to completed or failed.                                                           |
| Response Message | The response CIPP returned, which is where the reason for a failure appears.                                                        |
| Last Run         | When the test was delivered.                                                                                                        |

A failing test after a migration is the clearest symptom of the URL mismatch described above.

{% include "../../../../.gitbook/includes/feature-request.md" %}

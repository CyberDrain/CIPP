# Sherweb

The Sherweb integration connects CIPP to your Sherweb CSP account so that Microsoft 365 licenses and subscriptions can be managed from within CIPP. Once configured and mapped, you can purchase licenses while creating users, adjust subscription quantities from the CSP Licenses report, schedule decreases to land at renewal, and optionally automate migrations from a legacy CSP.

{% hint style="info" %}
Not a Sherweb partner yet? See [Sherweb Cloud Services for MSPs](https://www.sherweb.com/partners/).
{% endhint %}

## Prerequisites

You need an active Sherweb partner account with access to the Cumulus portal, and API access enabled on that account. Three values are collected from Sherweb and entered into CIPP.

## Obtaining Your API Credentials

{% stepper %}
{% step %}
#### Open the API settings in Cumulus

Sign in to the Sherweb Cumulus portal and go to the API security page for your account, at `https://cumulus.sherweb.com/partners/<your-account-name>/security/apis`.
{% endstep %}

{% step %}
#### Create an application

Create a new application and give it a recognisable name, such as _CIPP_.
{% endstep %}

{% step %}
#### Store the credentials

Record the **Client ID**, **Subscription Key** and **Client Secret** somewhere secure, such as a password manager or your documentation platform. The secret is not retrievable from Cumulus afterwards.
{% endstep %}
{% endstepper %}

## Configuring the Integration in CIPP

{% stepper %}
{% step %}
#### Enable the integration

Turn on **Enable Integration**. The remaining fields stay disabled until it is on.
{% endstep %}

{% step %}
#### Enter the credentials

Enter the **Client ID**, **Subscription Key** and **Client Secret** collected from Cumulus.
{% endstep %}

{% step %}
#### Restrict purchasing (optional)

Use **Select CIPP roles that are allowed to purchase licenses** to limit which custom roles may buy or change Sherweb subscriptions. Leaving it empty places no restriction.
{% endstep %}

{% step %}
#### Save and test

Select **Submit** to save, then select **Test**. A green banner confirms CIPP can authenticate against Sherweb; a red banner means the credentials need checking.
{% endstep %}

{% step %}
#### Map your tenants

Move to the **Tenant Mapping** tab and pair each CIPP tenant with its Sherweb customer, then select **Submit**.
{% endstep %}
{% endstepper %}

## Settings

| Setting                                                  | Description                                                                                                                                                      |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enable Integration                                       | Turns the integration on. Every other setting, the **Test** button, and the **Tenant Mapping** tab remain unavailable until this is enabled and saved.           |
| Client ID                                                | The Client ID of the application created in the Sherweb Cumulus portal.                                                                                          |
| Subscription Key                                         | The subscription key used to access the Sherweb API.                                                                                                             |
| Client Secret                                            | The client secret used to authenticate the application. Stored securely and masked once saved.                                                                   |
| Select CIPP roles that are allowed to purchase licenses  | Restricts subscription changes to CIPP users holding one of the selected custom roles. Leave empty to allow anyone with the relevant CIPP permission.            |
| Enable automated migration to Sherweb                    | Reveals the automated migration options described below.                                                                                                         |
| Select how you'd like automated migrations to be handled | The migration strategy: notify only, buy and notify, or buy and cancel.                                                                                          |
| Select the vendor to automatically migrate from          | The legacy CSP whose subscriptions should be canceled. Only appears for the buy and cancel strategy, and currently only supports Pax8.                          |
| Select the type of license to automatically migrate to   | The commitment term for licenses purchased at Sherweb: `Yearly` (Y1Y), `Annual paid monthly` (M1Y), or `Monthly` (M2M). Appears for any strategy that purchases. |
| Pax8 Client ID                                           | The Client ID of your Pax8 API application. Only appears when migrating from Pax8.                                                                               |
| Pax8 Client Secret                                       | The client secret of your Pax8 API application. Only appears when migrating from Pax8.                                                                           |

{% hint style="warning" %}
The role restriction applies to subscription changes made through CIPP by a signed-in user or an API client. It does not apply to changes made by scheduled tasks or by the automated migration process, which run without a caller identity.
{% endhint %}

## Tenant Mapping

The **Tenant Mapping** tab pairs each CIPP tenant with a Sherweb customer, so CIPP knows which Sherweb account to place orders against. License purchasing and automated migrations both depend on this, and an unmapped tenant is simply skipped.

To map manually, choose a tenant, choose the matching entry under **Select Sherweb Company**, and select the add button. **Automap Companies** fills in matches automatically, and the refresh button reloads the customer list from Sherweb. Mappings are only written when you select **Submit**.

| Column          | Description                                               |
| --------------- | --------------------------------------------------------- |
| IntegrationName | The name of the Sherweb customer the tenant is mapped to. |
| Tenant          | The display name of the mapped Microsoft 365 tenant.      |
| TenantDomain    | The default domain name of the mapped tenant.             |
| TenantId        | The tenant's Microsoft customer ID.                       |

Individual mappings can be removed with the **Delete Mapping** row action.

{% hint style="info" %}
Automapping compares the tenant's display name with the Sherweb customer name, ignoring case, punctuation and trailing legal suffixes such as Ltd, Limited, LLC, Inc, GmbH or BV. Where more than one Sherweb customer normalises to the same name the match is ambiguous, so it is left for you to map manually. Always review the proposed matches before saving.
{% endhint %}

## Purchasing and Managing Licenses

With the integration enabled and the tenant mapped, license actions become available in several places.

When adding or editing a user, selecting a license with no available seats reveals **0 Licenses available. Purchase new license?**. Enabling it lets you pick a **Sherweb License** to buy, and CIPP assigns the license to the user once it becomes available.

The Add Subscription page purchases a new subscription outright, and requires you to confirm that the purchase is made under your terms with Sherweb.

The CSP Licenses report carries row actions for existing subscriptions.

| Action                                 | Description                                                                                                                    |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Increase license count by 1            | Adds a single seat to the subscription immediately.                                                                            |
| Decrease license count by 1            | Removes a single seat from the subscription immediately.                                                                       |
| Increase license count                 | Adds a chosen number of seats to the subscription immediately.                                                                 |
| Decrease license count                 | Removes a chosen number of seats from the subscription immediately.                                                            |
| Schedule decrease of 1 at next renewal | Creates a scheduled task to remove a seat shortly before the subscription's renewal date, defaulting to three days beforehand. |
| Cancel Subscription                    | Cancels the subscription entirely.                                                                                             |

{% hint style="info" %}
A scheduled decrease checks the tenant's actual assignment state before it runs, and only proceeds when at least the requested number of seats is genuinely unassigned. If they are all in use the task completes without changing anything, so a seat that has been reassigned in the meantime is never pulled out from under a user.
{% endhint %}

## Automated Migrations

Automated migrations identify licenses at a non-Sherweb CSP that are approaching their transfer window, and — depending on the strategy chosen — notify you, purchase the equivalent license at Sherweb, or additionally cancel the legacy subscription.

Once the integration is enabled, CIPP registers a daily background check for each mapped tenant. Each run looks for subscriptions renewing within the next seven days, compares them against the subscriptions already held at Sherweb, and treats anything without an equivalent as a candidate for migration.

{% hint style="danger" %}
Only enable automated migrations after extensive testing. Run with the notify strategy for at least a month before allowing automatic purchases. Neither Sherweb nor CyberDrain is responsible for purchases made through the API.
{% endhint %}

{% stepper %}
{% step %}
#### Enable automated migrations

Turn on **Enable automated migration to Sherweb**. Further options appear as you make selections.
{% endstep %}

{% step %}
#### Choose a strategy

Under **Select how you'd like automated migrations to be handled**, choose one:

**Notify only** raises an alert when a subscription enters its cancellation window, and takes no other action.

**Buy and notify** purchases the matching Sherweb license and alerts you.

**Buy and cancel** purchases the matching Sherweb license and cancels the legacy subscription at the previous CSP.
{% endstep %}

{% step %}
#### Choose the vendor to migrate from

For the buy and cancel strategy, select the legacy CSP under **Select the vendor to automatically migrate from**. Pax8 is currently the only supported vendor.
{% endstep %}

{% step %}
#### Choose the commitment term

For any strategy that purchases, select the term under **Select the type of license to automatically migrate to**: `Yearly`, `Annual paid monthly`, or `Monthly`.
{% endstep %}

{% step %}
#### Enter Pax8 credentials

When migrating from Pax8, enter the **Pax8 Client ID** and **Pax8 Client Secret** from your Pax8 API application.
{% endstep %}

{% step %}
#### Save

Select **Submit** to store the configuration.
{% endstep %}
{% endstepper %}

Alerts are delivered by email, to your PSA, and by webhook, following your alert configuration. Purchases are matched to the Sherweb catalog on the Microsoft SKU ID together with the commitment term you selected; if no catalog entry matches, the purchase is not attempted and you receive a failure alert instead. Cancellation failures at Pax8 are alerted the same way, so a purchase that succeeds while the cancellation fails will not go unnoticed.

{% hint style="warning" %}
Matching relies on subscription and SKU IDs, and will improve as Sherweb exposes more SKU detail. Review the notifications from a notify-only period before trusting automated purchasing on your own catalog.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

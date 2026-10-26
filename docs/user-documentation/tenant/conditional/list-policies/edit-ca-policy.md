# Edit CA Policy

This page opens an existing Conditional Access policy in a structured editor, laid out to mirror the sections in the Entra admin center. The current settings are loaded from the tenant, so you are always editing the live policy rather than a copy. Review changes carefully before saving, since an overly restrictive policy can lock users, or you, out of the tenant.

The editor is built from the Graph schema, so it exposes conditions the policy list does not show as columns, including risk levels, device filters, and session controls.

## Policy Basics

| Field        | Description                                                                |
| ------------ | -------------------------------------------------------------------------- |
| Display Name | The name of the policy. Required.                                          |
| Policy State | Whether the policy is enabled, disabled, or in report-only mode. Required. |

## Users and Groups

Defines who the policy applies to. Entra stores the assigned users and groups as object IDs; the editor resolves them to names when it opens, and the four pickers search the tenant as you type, so you pick the account or group by name rather than looking up its ID first.

| Field                   | Description                                                                                                                                                              |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Include Users           | The users the policy targets, shown as display name with the user principal name in brackets. `All`, `None` and `GuestsOrExternalUsers` are offered as fixed options alongside the search results. |
| Exclude Users           | Users exempt from the policy. `GuestsOrExternalUsers` is offered as a fixed option.                                                                                    |
| Include Groups          | The groups the policy targets, shown by display name.                                                                                                                    |
| Exclude Groups          | Groups exempt from the policy.                                                                                                                                           |
| Include Directory Roles | Directory roles the policy targets, for scoping to administrators.                                                                                                       |
| Exclude Directory Roles | Directory roles exempt from the policy.                                                                                                                                  |

{% hint style="info" %}
Type at least two characters to search. The search matches the start of any word in a display name, user principal name or mail address, so `smi` finds **John Smith**. A user or group that has been deleted since it was assigned cannot be resolved and shows its raw object ID instead; remove it from the policy if it is no longer wanted. Pasting an object ID still works, for an account the search does not surface.
{% endhint %}

### Include or Exclude Guests or External Users

Two matching blocks, **Include Guests or External Users** and **Exclude Guests or External Users**, targeting people from outside the tenant by category rather than by naming individual accounts. The fields are the same on both sides.

| Field                                    | Description                                                                                                                                                                                       |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| External User Types to Include / Exclude | The categories of external user the policy targets or exempts, such as service providers or B2B collaboration guests.                                                                             |
| Tenant Scope                             | Whether the block covers all external tenants or only named ones. Appears once an external user type is selected, and is only meaningful for genuinely external users rather than internal guests. |
| External Tenant IDs                      | The tenant GUIDs to scope to. Appears only when the scope is set to specific tenants.                                                                                                             |

{% hint style="info" %}
Excluding your own partner tenant here is what the **Add service provider exception to policy** action on the policy list does for you. Use that action rather than setting this by hand unless you need something more specific.
{% endhint %}

{% hint style="warning" %}
Entra ID rejects an include block that is combined with `All`, `None` or `GuestsOrExternalUsers` under **Include Users**. The editor warns you as soon as the combination is set, but does not stop you saving it, so clear **Include Users** or drop the external user types first rather than waiting for Entra to refuse the save.
{% endhint %}

## Cloud Apps or Actions

| Field                                | Description                                                                                |
| ------------------------------------ | ------------------------------------------------------------------------------------------ |
| Include Applications                 | The applications the policy targets.                                                       |
| Exclude Applications                 | Applications exempt from the policy.                                                       |
| User Actions (instead of cloud apps) | Targets a user action, such as registering security information, in place of applications. |
| Authentication Context               | Authentication context references the policy protects, used in place of cloud apps.        |

### Application Filter

Targets applications by attribute rather than by name, which keeps the policy current as applications are added.

| Field                   | Description                                                                                   |
| ----------------------- | --------------------------------------------------------------------------------------------- |
| Application Filter Mode | Whether applications matching the rule are included or excluded.                              |
| Application Filter Rule | The filter expression, for example `application.customSecurityAttributes.App.Sensitivity -eq "High"`. |

## Conditions

| Field             | Description                                                                                               |
| ----------------- | --------------------------------------------------------------------------------------------------------- |
| Client App Types  | The client app types the policy applies to, for example browser or mobile apps. At least one is required. |
| Include Platforms | Device platforms the policy targets.                                                                      |
| Exclude Platforms | Device platforms exempt from the policy.                                                                  |
| Include Locations | Named locations the policy targets.                                                                       |
| Exclude Locations | Named locations exempt from the policy.                                                                   |

### Device Filter

| Field              | Description                                                                |
| ------------------ | -------------------------------------------------------------------------- |
| Device Filter Mode | Whether devices matching the rule are included or excluded.                |
| Device Filter Rule | The filter expression, for example `device.extensionAttribute1 -eq "SAW"`. |

### Authentication Flows

| Field                                | Description                                                                                                  |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| Authentication Flow Transfer Methods | The authentication flows the policy applies to: **Device code flow**, **Authentication transfer**, or both. |

### Risk Levels

Marked in the interface as requiring **Entra ID P2**.

| Field                         | Description                                                  |
| ----------------------------- | ------------------------------------------------------------ |
| Sign-in Risk Levels           | Risk levels for the sign-in attempt that trigger the policy. |
| User Risk Levels              | Risk levels for the account itself that trigger the policy.  |
| Service Principal Risk Levels | Risk levels for workload identities that trigger the policy. |
| Insider Risk Levels           | Insider risk levels that trigger the policy.                 |

### Workload Identities

Marked in the interface as requiring **Workload Identities Premium**. Scopes the policy to service principals instead of users, which is what turns it into a workload identity policy. Leave these empty for an ordinary user policy.

| Field                         | Description                                                                                    |
| ----------------------------- | ------------------------------------------------------------------------------------------------ |
| Include Service Principals    | The service principals the policy targets, either all of them or specific object IDs.          |
| Exclude Service Principals    | Service principals exempt from the policy, by object ID.                                       |
| Service Principal Filter Mode | Whether service principals matching the rule are included or excluded.                         |
| Service Principal Filter Rule | The filter expression, for example `servicePrincipal.customSecurityAttributes.App.Tier -eq "1"`. |

## Grant Controls

What the policy requires before granting access.

| Field                          | Description                                                                                 |
| ------------------------------ | ------------------------------------------------------------------------------------------- |
| Grant Operator                 | Whether the built-in controls are combined with AND or OR.                                  |
| Built-in Controls              | The requirements to grant access, such as multifactor authentication or a compliant device. |
| Authentication Strength Policy | An authentication strength policy to require in place of plain MFA.                         |
| Terms of Use                   | Terms of use the user must accept.                                                          |
| Custom Controls                | Legacy custom controls from an external identity provider, referenced by ID.                |

A grant operator is required as soon as any of these carry a value, custom controls included.

## Session Controls

Collapsed by default, since most policies do not use these.

| Field                            | Description                                                                                                                    |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Enable App Enforced Restrictions | Hands session limits to the application itself, used by SharePoint and Exchange to restrict downloads.                         |
| Enable App Control               | Routes the session through Defender for Cloud Apps.                                                                            |
| Control Type                     | How the session is proxied when app control is enabled.                                                                        |
| Enable Sign-in Frequency         | Forces reauthentication on a schedule.                                                                                         |
| Interval Mode                    | Whether the frequency is a recurring period or a fixed time.                                                                   |
| Value                            | The number of units in the sign-in frequency.                                                                                  |
| Unit                             | Hours or days.                                                                                                                 |
| Auth Type                        | Which authentication the frequency applies to.                                                                                 |
| Enable Persistent Browser        | Controls whether the browser session persists across restarts.                                                                 |
| Persistence Mode                 | Whether sessions are always persistent or never persistent.                                                                    |
| Disable Resilience Defaults      | Stops Entra extending existing sessions during an outage. Leaving resilience defaults on is the safer choice for most tenants. |

{% hint style="info" %}
Saving writes the policy as the editor shows it rather than merging with what the tenant already had. Anything you clear here, whether an exclusion, a platform condition or a session control, is cleared on the policy itself.
{% endhint %}

{% hint style="warning" %}
Test changes with the policy set to report only before enabling it, particularly when adding grant controls or narrowing the users the policy applies to. A policy that excludes no break-glass account can remove your own access to the tenant.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

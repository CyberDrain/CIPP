# Create CA Template

This page builds a Conditional Access template from scratch, using the same structured editor as the policy editor. Nothing is deployed when you save: the template is stored in CIPP, ready to deploy to any tenant, add to a standard, or push to a GitHub repository.

Because the template is not tied to a tenant, the editor asks you to name users, groups, and locations rather than pick them from a directory. Those names are resolved against the target tenant at deployment time.

New templates default to a state of **Report-only**, so a template deployed without changing the state will log what it would have done rather than enforce anything.

## Policy Basics

| Field        | Description                                                                                          |
| ------------ | ---------------------------------------------------------------------------------------------------- |
| Display Name | The name of the policy the template creates. Required.                                               |
| Policy State | Whether the deployed policy is enabled, disabled, or report only. Defaults to Report-only. Required. |

## Users and Groups

| Field                   | Description                                                        |
| ----------------------- | ------------------------------------------------------------------ |
| Include Users           | The users the policy targets.                                      |
| Exclude Users           | Users exempt from the policy.                                      |
| Include Groups          | The groups the policy targets.                                     |
| Exclude Groups          | Groups exempt from the policy.                                     |
| Include Directory Roles | Directory roles the policy targets, for scoping to administrators. |
| Exclude Directory Roles | Directory roles exempt from the policy.                            |

### Include or Exclude Guests or External Users

Two matching blocks, **Include Guests or External Users** and **Exclude Guests or External Users**, targeting people from outside the tenant by category rather than by naming individual accounts. The fields are the same on both sides.

| Field                                    | Description                                                                                                       |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| External User Types to Include / Exclude | The categories of external user the policy targets or exempts, such as service providers or B2B collaboration guests. |
| Tenant Scope                             | Whether the block covers all external tenants or only named ones. Appears once an external user type is selected. |
| External Tenant IDs                      | The tenant GUIDs to scope to. Appears only when the scope is set to specific tenants.                             |

{% hint style="warning" %}
Entra ID rejects an include block that is combined with `All`, `None` or `GuestsOrExternalUsers` under **Include Users**. The editor warns you as soon as the combination is set, but does not stop you saving the template, so the deployment is what fails.
{% endhint %}

## Cloud Apps or Actions

| Field                                | Description                                                                                |
| ------------------------------------ | ------------------------------------------------------------------------------------------ |
| Include Applications                 | The applications the policy targets.                                                       |
| Exclude Applications                 | Applications exempt from the policy.                                                       |
| User Actions (instead of cloud apps) | Targets a user action, such as registering security information, in place of applications. |
| Authentication Context               | Authentication context references the policy protects, used in place of cloud apps.        |

Authentication contexts are matched in the target tenant by display name when the template is deployed, and one that does not exist yet is created there, so a context can be referenced without existing in every tenant first.

### Application Filter

Targets applications by attribute rather than by name, which keeps the policy current as applications are added.

| Field                   | Description                                                                                           |
| ----------------------- | ------------------------------------------------------------------------------------------------------- |
| Application Filter Mode | Whether applications matching the rule are included or excluded.                                      |
| Application Filter Rule | The filter expression, for example `application.customSecurityAttributes.App.Sensitivity -eq "High"`. |

## Conditions

| Field             | Description                                                           |
| ----------------- | --------------------------------------------------------------------- |
| Client App Types  | The client app types the policy applies to. At least one is required. |
| Include Platforms | Device platforms the policy targets.                                  |
| Exclude Platforms | Device platforms exempt from the policy.                              |
| Include Locations | Named locations the policy targets, referenced by name.               |
| Exclude Locations | Named locations exempt from the policy, referenced by name.           |

### Device Filter

| Field              | Description                                                                |
| ------------------ | -------------------------------------------------------------------------- |
| Device Filter Mode | Whether devices matching the rule are included or excluded.                |
| Device Filter Rule | The filter expression, for example `device.extensionAttribute1 -eq "SAW"`. |

### Risk Levels

{% hint style="warning" %}
These require **Entra ID P2**. Usage of these without proper licensing could risk your client's tenant and your partner status.
{% endhint %}

| Field                         | Description                                                  |
| ----------------------------- | ------------------------------------------------------------ |
| Sign-in Risk Levels           | Risk levels for the sign-in attempt that trigger the policy. |
| User Risk Levels              | Risk levels for the account itself that trigger the policy.  |
| Service Principal Risk Levels | Risk levels for workload identities that trigger the policy. |
| Insider Risk Levels           | Insider risk levels that trigger the policy.                 |

### Authentication Flows

| Field                                | Description                                                                          |
| ------------------------------------ | ------------------------------------------------------------------------------------ |
| Authentication Flow Transfer Methods | The authentication transfer methods the policy applies to, such as device code flow. |

### Workload Identities

{% hint style="warning" %}
These require **Workload Identities Premium** in the target tenant. Usage of these without proper licensing could risk your client's tenant and your partner status.
{% endhint %}

Scopes the policy to service principals instead of users, which is what turns it into a workload identity policy. Leave these empty for an ordinary user policy. Service principals are referenced by object ID, which is tenant-specific, so a template using them is not portable between tenants in the way a user or group reference is.

| Field                         | Description                                                                                      |
| ----------------------------- | -------------------------------------------------------------------------------------------------- |
| Include Service Principals    | The service principals the policy targets, either all of them or specific object IDs.            |
| Exclude Service Principals    | Service principals exempt from the policy, by object ID.                                         |
| Service Principal Filter Mode | Whether service principals matching the rule are included or excluded.                           |
| Service Principal Filter Rule | The filter expression, for example `servicePrincipal.customSecurityAttributes.App.Tier -eq "1"`. |

## Grant Controls

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

## Named Locations

This section is unique to templates. Named locations defined here are stored inside the template and recreated in the target tenant on deployment, or matched to an existing location of the same display name. Reference them by name in the **Include Locations** and **Exclude Locations** fields under Conditions.

Use **Add Named Location** to add an entry, and the delete icon on any entry to remove it. Each entry has a display name and a location type, and the remaining fields depend on the type chosen.

| Field         | Description                                                                          |
| ------------- | ------------------------------------------------------------------------------------ |
| Display Name  | The name of the location. This is the name you reference under Conditions. Required. |
| Location Type | Either Countries / Regions or IP Ranges. Required.                                   |

Countries and IP ranges can come from a List variable per tenant; see the example under Custom Variables.

### IP Ranges

| Field                          | Description                                                                                                |
| ------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| IP Ranges (CIDR, one per line) | The address ranges in CIDR notation, one per line, for example `203.0.113.0/24`. At least one is required. |
| Mark as Trusted Location       | Marks the location as trusted, which some policies and risk evaluations treat differently.                 |

### Countries / Regions

| Field                               | Description                                                                                              |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------- |
| Countries / Regions                 | The countries or regions the location covers. At least one is required.                                  |
| Country Lookup Method               | Whether the country is determined from the client IP address or from the Authenticator app's GPS signal. |
| Include Unknown Countries / Regions | Includes addresses that cannot be mapped to a country.                                                   |

### Keeping a template's locations current

A template built from an existing policy, whether imported through **Browse Catalog** or created from a tenant's own Conditional Access policy, stores a copy of each named location that policy references as it stood at that moment. The copy is a point in time record rather than a live link back to the tenant the template came from, so changing the ranges on the original named location afterwards leaves the template holding the old ones, and every tenant deployed from it carries on receiving them.

There is no resync action. Bring the ranges up to date on [edit.md](edit.md "mention"), which changes the template in place. Building a new template from the corrected policy produces a separate template with its own GUID instead, and a standard already pointing at the original carries on using the original.

On deployment, each of the template's named locations is matched to one of the same display name in the target tenant. Where the deployment overwrites, that location is rewritten to the template's stored values; otherwise the tenant's existing location is left as it is and referenced by the policy. **Overwrite Existing Policy** in the deploy drawer controls this for a manual deployment.

{% hint style="warning" %}
A template applied through a standard always overwrites. Correcting a customer tenant's named location directly on [README.md](../list-named-locations/README.md "mention") is undone the next time that standard runs, so correct the ranges on the template instead.
{% endhint %}

{% hint style="info" %}
A template deployed to a tenant is not linked to it afterwards. Editing the template later does not change policies already deployed from it, unless the template is applied through a standard, which redeploys on drift.
{% endhint %}

## Custom Variables

Any field in this editor accepts a variable, written as `%variablename%`, which is replaced with the target tenant's value each time the template is deployed. That is what lets one template cover an estate where the details differ per client, such as a site name or an office IP range.

Substitution happens before CIPP matches names in the target tenant, so a named location, authentication strength, or authentication context whose name is built from a variable is matched to the existing object of that name rather than created again on every deployment. Because the whole template is substituted at once, a variable used in a **Named Locations** display name resolves to the same value where it is referenced under **Include Locations** or **Exclude Locations**, so write the reference with the same variable text rather than a resolved value.

Values are set for every tenant in [global-variables.md](../../administration/tenants/global-variables.md "mention"), or for one tenant in the Custom Variables box on [edit.md](../../manage/edit.md "mention"), where the tenant's own value wins.

A **List** variable used in Include or Exclude Users, Groups or Locations expands into one entry per value, so a single `%breakglassaccounts%` can exclude two accounts in one tenant and three in another. User, group and location values may be display names: names are resolved to IDs in the target tenant on deployment, whichever group and user option is chosen in the deploy drawer, and a location name is matched to the tenant's existing named location when the template does not define it. A name that matches nothing stops the deployment with an error naming it, rather than being dropped.

For example, a policy that blocks sign-ins from outside a client's countries and offices embeds two named locations and excludes both under Conditions. Their values come from List variables rather than being typed into the template:

| Named Location    | Type                | Field               | Value                |
| ----------------- | ------------------- | ------------------- | -------------------- |
| Allowed Countries | Countries / Regions | Countries / Regions | `%allowedcountries%` |
| Office IPs        | IP Ranges           | IP Ranges           | `%officeips%`        |

Each tenant then sets its own values, one per line. `allowedcountries` takes two-letter country codes:

```
NL
BE
```

and `officeips` takes CIDR ranges, IPv4 or IPv6:

```
203.0.113.0/24
198.51.100.10/32
```

On deployment each tenant's locations are created, or updated in place, with that tenant's countries and ranges, so one template covers every client. Changing a tenant's variable takes effect on the next deployment or standard run.

Type `%` in the Users, Groups and Locations fields to pick from the [variable-auto-complete.md](../../../shared-features/variable-auto-complete.md "mention") list.

{% hint style="warning" %}
A variable with no value for the tenant being deployed to stops the deployment with an error naming it. See Unresolved Variables on [global-variables.md](../../administration/tenants/global-variables.md "mention").
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

# Setting Search

Setting Search finds an Intune setting by its name or ID in the selected tenant and shows every policy that configures it, the value each policy sets, and the devices those policies apply to. Use it to answer questions such as "which policy sets the minimum password length?" or "do any of our policies disagree about this setting?" without opening each policy in turn. Settings catalog policies, device configuration profiles (including custom OMA-URI settings), compliance policies, update profiles and app policies are all covered. Administrative Templates and Endpoint Security policies created before the settings catalog are not searched.

{% hint style="info" %}
Setting Search works on a single tenant. When the tenant selector is set to All Tenants or a tenant group, the page asks you to pick a tenant instead.
{% endhint %}

## Search

| Field              | Description                                                                                                 |
| ------------------ | ----------------------------------------------------------------------------------------------------------- |
| Setting name or ID | Part of the setting's display name or its ID. The match is not case-sensitive. Enter at least 3 characters. |

Select **Search** or press Enter to run the search. At most 500 settings are returned; if more match, a notice asks you to refine the search.

## Table Details

| Column       | Description                                                                                                                                                                        |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Setting Name | The name of the setting.                                                                                                                                                           |
| Category     | The settings catalog category the setting belongs to, or the policy type for other settings.                                                                                       |
| Policy Types | The kinds of policy that configure the setting.                                                                                                                                    |
| Policy Count | The number of policies that configure the setting.                                                                                                                                 |
| Device Count | The number of distinct devices those policies report on. A device covered by several of the policies is counted once. Shows **No data** when none of the policies has device data. |

Device Count shows **No data** for policy types that have no device report, such as update profiles and app policies, and for policies that have not been synced yet. A count of 0 means device data exists but no devices have reported.

## Setting Details

Selecting a row opens a flyout with the setting's details and two tables.

**Policies** lists each policy that configures the setting, its policy type, the value it sets and its own device count.

**Devices** lists the devices those policies apply to, with each device's status for the policy, when it last reported, its user and the policy name.

If the policies set the setting to different values, a **This setting isn't aligned** warning appears above the tables, summarising which values are set by how many policies. Policies with different values for the same setting can conflict on devices that receive more than one of them.

Values that are not shown in clear text appear as:

| Value       | Meaning                                                      |
| ----------- | ------------------------------------------------------------ |
| (encrypted) | An encrypted custom OMA-URI value.                           |
| (secret)    | A secret value, such as a password or key.                   |
| (hidden)    | A large payload, such as a custom XML or JSON configuration. |

These values are left out when checking whether a setting is aligned, and the warning says how many were skipped.

{% hint style="warning" %}
Setting Search reads CIPP's cached copy of the tenant's Intune policies, not Graph directly. A policy created or changed since the last sync appears once the cache has been refreshed.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

# Licenses

Excluded licenses are SKUs that CIPP leaves out of its license counts and reporting. The list is seeded with a set of defaults covering free and trial SKUs that would otherwise inflate reports, and you can add or remove entries to suit your own reporting. Exclusions apply across the whole instance rather than per tenant.

## Exclusion Types

An exclusion works in one of two ways, shown in the Exclusion Type column.

| Type                      | Description                                                                                                                                                                              |
| ------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Excluded Everywhere       | The license is left out of license reporting, alerts, and the data sent to integrations such as Gradient. This is the default for a newly added exclusion.                               |
| Excluded from Alerts Only | The license still appears in license reports and integration data, but is ignored when alerts are evaluated. Use this for SKUs you want visibility of without being notified about them. |

Separately from the exclusion type, each entry carries a flag controlling whether the license still appears in CIPP's license pickers.

{% hint style="info" %}
Excluding a license hides it from reporting, but it does not stop the license existing in the tenant or prevent it being assigned in Microsoft 365. Allow an excluded license back into the pickers with **Show in License Dropdowns** when you still need to assign it from within CIPP.
{% endhint %}

## Page Actions

| Button                                                              | Description                                                          |
| ------------------------------------------------------------------- | -------------------------------------------------------------------- |
| [#add-excluded-license](licenses.md#add-excluded-license "mention") | Adds a license to the exclusion list.                                |
| [#restore-defaults](licenses.md#restore-defaults "mention")         | Re-applies CIPP's default exclusions from its bundled configuration. |

### Add Excluded License

The dialog offers two ways of identifying the license.

| Field          | Description                                                                                                                                                                                                |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Advanced Mode  | Switches from picking a known license to entering the details by hand. Leave off unless the license you want is not in the list.                                                                           |
| Select License | The license to exclude, chosen from CIPP's built-in list of Microsoft 365 SKUs. Where two products share a display name, the GUID is appended so you can tell them apart. Shown when Advanced Mode is off. |
| GUID           | The SKU identifier of the license, for example `f30db892-07e9-47e9-837c-80727f46fd3d`. Shown when Advanced Mode is on.                                                                                     |
| SKU Name       | The display name to record against the GUID, for example `MICROSOFT FLOW FREE`. Shown when Advanced Mode is on.                                                                                            |

{% hint style="info" %}
Microsoft publish the full list of product names, SKU identifiers and service plans in their [licensing service plan reference](https://learn.microsoft.com/entra/identity/users/licensing-service-plan-reference), which is the place to look up a GUID for Advanced Mode.
{% endhint %}

A license added this way is set to Excluded Everywhere. Change it afterwards with the **Only Exclude from Alerts** row action if you want the narrower behavior.

### Restore Defaults

| Field                                                        | Description                                                                                                                                                                     |
| ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Full Reset (clear all entries including manually added ones) | Clears the entire list before restoring the defaults. Leave this off to add any missing defaults while keeping your own entries and any changes you have made to existing ones. |

{% hint style="danger" %}
A full reset deletes every entry in the list, including licenses you added yourself and any exclusions you switched to alerts only. There is no undo, so leave the switch off unless you genuinely want to start again.
{% endhint %}

## Table Details

| Column                   | Description                                                                         |
| ------------------------ | ----------------------------------------------------------------------------------- |
| Product Display Name     | The name of the excluded license.                                                   |
| GUID                     | The SKU identifier of the license.                                                  |
| Exclusion Type           | Whether the license is excluded everywhere or only from alerts.                     |
| Show In License Dropdown | Whether the license still appears in CIPP's license pickers despite being excluded. |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Only Exclude from Alerts</td><td>Narrows the exclusion so the license is ignored by alerts but still appears in reports and integration data.</td><td>true</td></tr><tr><td>Show in License Dropdowns</td><td>Makes the license selectable in CIPP's license pickers again. Only offered for licenses currently hidden from them.</td><td>true</td></tr><tr><td>Hide from License Dropdowns</td><td>Removes the license from CIPP's license pickers. Only offered for licenses currently shown in them.</td><td>true</td></tr><tr><td>Delete Exclusion</td><td>Removes the license from the exclusion list, so it is counted and reported on again.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}

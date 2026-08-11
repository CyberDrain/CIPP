# Sign-in Report

This report queries the tenant's sign-in logs directly, so a specific sign-in can be found and examined without leaving CIPP. By default it returns interactive user sign-ins from the last seven days, and the filter card above the table changes what is asked for.

{% hint style="warning" %}
Sign-in logs require Microsoft Entra ID P1 or higher. Without that licensing Microsoft returns no data, so an empty table means the logs are unavailable rather than that nobody signed in.
{% endhint %}

## Filter Options

The filter card is collapsed until opened. Changing a value does nothing until **Apply Filter** is selected, at which point the table is re-queried and the card collapses again.

| Field                         | Description                                                                                                                                                         |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Days                          | How far back to look. Defaults to 7.                                                                                                                                |
| Results per page ($top)       | How many records to request at a time. Defaults to 500, and lowering it helps when the report is slow to load.                                                      |
| Sign-In Event Type            | Which kinds of sign-in to include: Interactive, Non-Interactive, Service Principal or Managed Identity. Defaults to Interactive, and more than one can be selected. |
| User (startsWith UPN)         | Narrows to users whose sign-in name begins with the text entered.                                                                                                   |
| App (startsWith display name) | Narrows to applications whose name begins with the text entered.                                                                                                    |
| Conditional Access Result     | Narrows to sign-ins where Conditional Access returned Success, Failure or Not Applied.                                                                              |
| Error Codes                   | Narrows to specific sign-in error codes, listed with their meanings. Leave empty to include every result, successful or not.                                        |
| Hide Directory Sync Account   | Excludes the On-Premises Directory Synchronization Service Account, which otherwise dominates the results on a synchronised tenant. On by default.                  |

{% hint style="info" %}
The columns shown depend on the event types selected. User sign-ins show the user principal name, client app and authentication requirement; service principal and managed identity sign-ins show the service principal, application and target resource instead. Selecting both kinds shows the columns for both.
{% endhint %}

**Save as Preset** stores the current filter as a Graph Explorer preset under a name of your choosing, so a query you expect to run again can be reached from there. The saved preset records the number of days rather than the dates it resolved to, so it stays relative and returns the last seven days whenever it is next run rather than the same week forever.

## Table Details

The properties returned are for the Graph resource type `signIn`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/signin?view=graph-rest-beta#properties).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
The flyout on this page shows the complete sign-in record as raw JSON rather than a summarized list of fields. That is where the detail an investigation needs sits, including the Conditional Access policies evaluated and their individual results, the device and client details, and the full authentication method breakdown.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

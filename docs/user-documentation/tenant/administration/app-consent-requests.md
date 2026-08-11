# App Consent Requests

Users who are blocked from consenting to applications themselves can ask an administrator to consent on their behalf. This page lists those requests for the selected tenant, showing who asked, for which application, why, and what has happened to the request since.

{% hint style="warning" %}
Requests only exist where the admin consent request workflow is turned on in the tenant. The **Enable App consent admin requests** standard turns it on, and it is normally paired with **Require admin consent for applications (Prevent OAuth phishing)**, which is what stops users consenting for themselves in the first place. Both are in [standards](../standards/ "mention").

To avoid requests sitting unnoticed, enable the **Alert on new apps in the application approval list** alert in [alert-configuration](alert-configuration/ "mention").
{% endhint %}

{% hint style="info" %}
This page needs a single tenant selected and does not support All Tenants.
{% endhint %}

## App Consent Request Filters

The panel above the table controls which requests are retrieved from the tenant. **Request Status** offers All, Pending, Expired and Completed. **Apply Filters** fetches the matching requests and collapses the panel; **Clear Filters** returns the selection to All.

The page opens with the filter already set to Pending, on the basis that outstanding requests are what usually matters, so the table will not show every request until the filter is changed.

The table's own filter menu additionally offers Pending requests, Expired requests and Completed requests, which filter the rows already retrieved rather than fetching afresh.

## Table Details

| Column                 | Description                                                                                                                                             |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Request Date           | When the user submitted the request.                                                                                                                    |
| Request User           | The user principal name of the person who asked for consent.                                                                                            |
| App Display Name       | The name of the application consent is being requested for.                                                                                             |
| App Id                 | The application (client) ID of that application.                                                                                                        |
| Request Reason         | The justification the user gave when raising the request.                                                                                               |
| Request Status         | The state of the request. Outstanding requests read `InProgress` here, matching Microsoft's own value rather than the Pending label used in the filter. |
| Reviewed By            | The user principal name of the administrator who acted on the request, once one has.                                                                    |
| Reviewed Justification | The reason the reviewer recorded when approving or denying.                                                                                             |
| Consent Url            | The admin consent link CIPP builds for the request, which is what the **Approve in Entra** action opens.                                                |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Review in Entra</td><td>Opens the admin consent requests view in the Microsoft Entra admin center, in a new tab. This opens the list of requests rather than the selected one.</td><td>false</td></tr><tr><td>Approve in Entra</td><td>Opens the Microsoft consent prompt for the selected application, in a new tab, built from the permissions the request is waiting on.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
The permissions being requested are not shown in the table or the flyout, and completing the prompt that **Approve in Entra** opens grants those permissions on behalf of the entire organization, not only the user who asked. Review the request in Entra, or the application itself, before approving.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

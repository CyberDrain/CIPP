# External Users

## Table Details

The properties returned are for the SharePoint PowerShell command `Get-SPOExternalUser`. For more information on the command please see the [Microsoft documentation](https://learn.microsoft.com/en-us/powershell/module/microsoft.online.sharepoint.powershell/get-spoexternaluser?view=sharepoint-ps).&#x20;

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Remove Guest Access</td><td>Fully removes external access for the selected guest. Deletes their Entra guest account (if one exists) and removes them from every site listed in the Sites column, so nothing is left orphaned. You'll be asked to confirm first. Any sharing links they hold are revoked separately from the Sharing Report, and the leftover SharePoint store entry ages out on its own. Available to users with SharePoint site write access.</td><td>true</td></tr></tbody></table>

***

{% include "../../../.gitbook/includes/feature-request.md" %}

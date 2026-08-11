# Connectors

This page lists the inbound and outbound mail flow connectors configured in the selected tenant's Exchange Online organization. From here you can enable, disable, or delete a connector, capture one as a reusable template, and deploy connectors out to other tenants. Viewing the list requires the `Exchange.Connector.Read` permission, and every action on the page requires `Exchange.Connector.ReadWrite`.

## Action Buttons

<details>

<summary>Deploy Connector</summary>

Opens a drawer that creates a connector in one or more tenants. Select the target tenants, then either pick a saved connector template to fill in the **Parameters (JSON)** box or type the JSON in yourself, and click **Deploy Connector**. If you are typing the JSON yourself, include a `cippConnectorType` property set to `Inbound` or `Outbound` so CIPP knows which kind of connector to create; templates picked from the list already carry it. The result for each tenant is shown in the drawer, and your tenant selection is kept so you can deploy another.

</details>

## Filters

Preset filters are available from the **Filters** button for **Inbound Connectors** and **Outbound Connectors** rows.

## Table Details

| Column                      | Description                                                                                                                                                                                   |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Name                        | The connector's name in Exchange Online.                                                                                                                                                      |
| Enabled                     | Whether the connector is currently active. A disabled connector keeps its configuration but carries no mail.                                                                                  |
| Comment                     | The free-text note stored with the connector, often used to record why it exists.                                                                                                             |
| Cippconnectortype           | Whether the connector handles mail arriving at the organization (`Inbound`) or leaving it (`Outbound`). Both directions are listed together on this page, so this is how you tell them apart. |
| Tls Sender Certificate Name | The certificate name a sending server must present before mail is accepted over an inbound connector.                                                                                         |
| Sender IP Addresses         | The addresses and ranges mail must arrive from for an inbound connector to apply.                                                                                                             |
| Is Transport Rule Scoped    | Whether the connector is used only when a transport rule routes mail to it, rather than for all mail that matches its settings.                                                               |
| Smart Hosts                 | The hosts an outbound connector relays mail through, such as an on-premises server or a filtering service.                                                                                    |
| Tls Settings                | How much encryption is required when mail is handed over, for example `EncryptionOnly` or `DomainValidation`.                                                                                 |
| Tls Domain                  | The domain checked against the receiving server's certificate when domain validation is required.                                                                                             |

Several columns only apply in one direction, so an inbound connector leaves the outbound-only columns empty and the other way round. The full set of properties behind each direction is described in the Microsoft documentation for [Get-InboundConnector](https://learn.microsoft.com/en-us/powershell/module/exchange/get-inboundconnector?view=exchange-ps) and [Get-OutboundConnector](https://learn.microsoft.com/en-us/powershell/module/exchange/get-outboundconnector?view=exchange-ps).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Create template based on connector</td><td>Saves the selected connector as a connector template on the <a data-mention href="list-connector-templates.md">list-connector-templates.md</a> page, so its settings can be redeployed to other tenants.</td><td>true</td></tr><tr><td>Enable Connector</td><td>Sets the selected connector to <code>Enabled</code> so mail starts flowing through it. Greyed out for a connector that is already enabled, and for a bulk selection unless every selected connector is disabled.</td><td>true</td></tr><tr><td>Disable Connector</td><td>Sets the selected connector to <code>Disabled</code>, which stops mail flowing through it while leaving its configuration in place. Greyed out for a connector that is already disabled, and for a bulk selection unless every selected connector is enabled.</td><td>true</td></tr><tr><td>Delete Connector</td><td>Permanently removes the selected connector from the tenant. Consider using <strong>Create template based on connector</strong> first if you might need to recreate it.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}

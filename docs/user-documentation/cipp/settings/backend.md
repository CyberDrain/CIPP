---
description: Get information on and access to the backend services powering CIPP.
---

# Backend

The Backend tab provides direct links into the Azure resources that run your CIPP instance. Each card opens the relevant blade in the Azure portal in a new tab, with the subscription, resource group and resource names already resolved for your deployment, which saves hunting through the portal for them.

{% hint style="info" %}
Hosted clients do not own the underlying Azure resources, so these links will not resolve for them. Use the backend management system at [management.cipp.app](https://management.cipp.app) instead.
{% endhint %}

## Available Links

Every card carries a **Launch** button that opens the corresponding Azure portal blade.

| Card                             | Description                                                                                                                                                   |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Resource Group                   | The container holding all CIPP resources in your tenant, with the exception of the SAM application, which lives outside it.                                   |
| Key Vault                        | The secrets store holding saved authentication details, including the SAM application credentials and integration API keys. Access is not granted by default. |
| Static Web App (Role Management) | Where users are invited to CIPP and their roles assigned.                                                                                                     |
| Function App (Deployment Center) | Deployment history and the GitHub connection used for continuous deployment, which is where the API is updated to a newer version.                            |
| Function App (Configuration)     | The application settings for the API, including the environment variables that control instance behavior.                                                    |
| Function App (Overview)          | Performance and usage information for the API, and the controls to stop and start it.                                                                         |
| Cloud Shell                      | Opens an Azure Cloud Shell session in a new window, preset to PowerShell.                                                                                     |

{% hint style="warning" %}
Stopping the Function App halts all CIPP background processing, including scheduled tasks, alerts and standards runs. Restarting it is usually the safer option when troubleshooting.
{% endhint %}

{% hint style="info" %}
To set the time zone used by the API, change the relevant application setting on the Function App Configuration page. Microsoft's [general settings documentation](https://learn.microsoft.com/en-us/azure/app-service/configure-common?tabs=portal#configure-general-settings) covers how application settings are edited.
{% endhint %}

## Cloud Shell

The Cloud Shell card behaves slightly differently from the others. **Launch** opens a PowerShell Cloud Shell in a separate browser window rather than a tab, and a second button, **Command Reference**, opens a flyout containing ready-made commands for your instance.

The commands in the flyout are generated with your own resource group, function app and static web app names already substituted, so they can be copied straight into the shell.

| Command                 | Purpose                                                                                                                                      |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Function App Config     | Returns the function app's name, status, location, runtime and application settings.                                                         |
| Function App Deployment | Returns the deployment source, showing the repository URL, branch, and whether deployment runs through GitHub Actions or manual integration. |
| Watch Function Logs     | Streams the function app log tail live, which is the quickest way to watch what the API is doing during a reproduction.                      |
| Static Web App Config   | Returns the static web app's name, custom domain, default hostname and repository URLs.                                                      |
| List CIPP Users         | Lists the users invited to CIPP together with their assigned roles, across all authentication providers.                                     |

{% hint style="info" %}
The **Command Reference** button is unavailable on hosted instances, since the commands operate on Azure resources a hosted client does not own.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

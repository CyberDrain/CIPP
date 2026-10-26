---
description: >-
  Use these steps when a CIPP function app has lost its required environment
  variables and you need to restore them manually without scripted access.
---

# Repairing Missing Function App Settings

{% hint style="warning" %}
This page applies only to the legacy Function App infrastructure, which no longer receives CIPP updates from 1 January 2027. Self-hosted instances need to move to the new infrastructure before then, see [migrating-to-the-new-infrastructure.md](../../setup/maintaining-cipp/migrating-to-the-new-infrastructure.md "mention").
{% endhint %}

## Prerequisites

* Access to the Azure Portal ([portal.azure.com](https://portal.azure.com/))
* **Contributor** (or higher) role on the resource group containing the function app
* The storage account connection string for the CIPP resource group (see [Retrieve Storage Connection String](repairing-missing-function-app-settings.md#retrieve-storage-connection-string) below)

## Identify Affected Function Apps

{% stepper %}
{% step %}
In the Azure Portal, navigate to **Resource Groups**.
{% endstep %}

{% step %}
Open the resource group for the affected CIPP instance, for example `CIPP`.
{% endstep %}

{% step %}
Locate the **Function App** resource. It is the one whose name contains **no hyphen**, for example `cippxyz123` rather than `cippxyz123-proc`.
{% endstep %}

{% step %}
Click the Function App to open it.
{% endstep %}

{% step %}
In the left menu, go to **Settings → Environment variables**.
{% endstep %}

{% step %}
Click the **App settings** tab.
{% endstep %}

{% step %}
Review the list. A healthy app should have **15+ settings**. Fewer than 10 indicates missing settings.
{% endstep %}
{% endstepper %}

## Retrieve Storage Connection String

You need the connection string for the storage account in the same resource group.

{% stepper %}
{% step %}
In the same resource group, find the **Storage account** (name starts with `cipp`, for example `cippstgabc123`).
{% endstep %}

{% step %}
Open it and go to **Security + networking → Access keys**.
{% endstep %}

{% step %}
Click **Show** next to **key1**.
{% endstep %}

{% step %}
Copy the full **Connection string** value. It looks like:

```
DefaultEndpointsProtocol=https;AccountName=cippstgabc123;AccountKey=<key>;EndpointSuffix=core.windows.net
```

Keep this, as it is the value for `AzureWebJobsStorage`.
{% endstep %}
{% endstepper %}

## Required Settings

Navigate to the function app → **Settings → Environment variables → App settings**.

Use **+ Add** for each missing setting. Use **Edit** if the key exists but has a wrong value.

Click **Apply** (bottom of page) then **Confirm** after adding all settings.

### Core Runtime Settings (all app types)

| Setting                           | Value                                            | Notes                                       |
| --------------------------------- | ------------------------------------------------ | ------------------------------------------- |
| `FUNCTIONS_WORKER_RUNTIME`        | `powershell`                                     | Must be lowercase                           |
| `FUNCTIONS_EXTENSION_VERSION`     | `~4`                                             |                                             |
| `AzureWebJobsStorage`             | `DefaultEndpointsProtocol=https;AccountName=...` | Full connection string from storage account |
| `WEBSITE_RUN_FROM_PACKAGE`        | _(see below)_                                    | URL to the zip package                      |
| `WEBSITE_ENABLE_SYNC_UPDATE_SITE` | `true`                                           |                                             |

#### WEBSITE\_RUN\_FROM\_PACKAGE value

In a self-hosted environment the package URL points to a zip file inside **your own storage account**. The easiest way to restore it correctly is to re-run the GitHub Actions deployment workflow, which will write the correct URL automatically.

See the CIPP documentation for instructions: [Setup Automatic API Updates](/broken/pages/Pjb7aq2bQTrbFJQfLNNv)

## Verify the Fix

After saving all settings (the function app will restart automatically):

{% stepper %}
{% step %}
Wait \~2 minutes for the restart to complete.
{% endstep %}

{% step %}
Function app → **Overview**: Status should show **Running**.
{% endstep %}

{% step %}
Function app → **Functions**: the function list should populate (5 functions visible).
{% endstep %}

{% step %}
If the list is empty after 5 minutes, check **Log stream** for startup errors.
{% endstep %}
{% endstepper %}

---
description: Installing Your CIPP
---

# Installation

Whether you opt to be hosted by CyberDrain or self-host, we've made installation of your instance a breeze. See below for instructions.

## CyberDrain Hosted Deployment

{% stepper %}
{% step %}
### Open the Management Portal

You will receive an email from GitHub once you complete your sponsorship payment directing you to [management.cipp.app](https://management.cipp.app/).
{% endstep %}

{% step %}
### Log In

Use the GitHub account you signed up for the sponsorship to log in to the management portal.&#x20;

{% hint style="warning" %}
If you used an organization account, please send in a support ticket to [helpdesk@cyberdrain.com](mailto:helpdesk@cyberdrain.com) with the organization GitHub account and a personal GitHub account. We will add the personal account to the sponsorship to allow you to log in.
{% endhint %}
{% endstep %}

{% step %}
### Start Onboarding

Click the Start Onboarding button to begin the installation process
{% endstep %}

{% step %}
### Choose "Deploy my Instance"

Click Next Step
{% endstep %}

{% step %}
### Complete the Form Details

{% hint style="warning" %}
Use caution when selecting your deployment region. You should choose a region that is geographically close to where you are located. This will provide your users with the best experience possible as you will have the lowest latency between your users and the server.
{% endhint %}
{% endstep %}

{% step %}
### Verify and Confirm

If the information looks correct, click Confirm.
{% endstep %}

{% step %}
### Monitor

You will be able to monitor progress. The management portal will refresh and show your instance information when completed. Alternatively, you can navigate away as you will receive an email once installation is completed.

{% hint style="info" %}
If you receive an error during installation rest assured that the helpdesk has been alerted and will work to resolve the error quickly.
{% endhint %}
{% endstep %}
{% endstepper %}

{% @storylane/embed subdomain="app" linkValue="8lif4yxgrpxs" url="https://app.storylane.io/share/8lif4yxgrpxs" %}

## Self-Hosted Deployment

{% stepper %}
{% step %}
### Confirm You’ve Met All Prerequisites

Before deploying, ensure you’ve completed everything in the [index.md](index.md "mention") section (Azure subscription, experience to manage complex azure environments, and all other requirements).
{% endstep %}

{% step %}
### Use Template to Deploy

This template creates all necessary resources in your selected region, including:

* **Azure Web App** (API) with a **Storage Account**
* **Azure Key Vault** for CIPP secrets
* **Azure App Service Plan** for your computing power
* Performance is impacted by your region selection. Make sure you choose the region closest to you for optimal performance.
* After you have completed the prerequisites in, select the button below to run the automated setup.

[![](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2FCyberDrain%2FCIPP%2Frefs%2Fheads%2Fdev%2Fdeployment%2Fcipp-deploy-azure-button.json)

{% hint style="danger" %}
**What if the deployment fails?** It’s simplest to **delete the resource group** in the Azure portal and try again. This ensures a clean slate.
{% endhint %}
{% endstep %}
{% endstepper %}

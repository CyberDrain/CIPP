---
description: This page covers everything you need before installing CIPP.
---

# Prerequisites

To get started you must follow or have the following ready. Click on the links for instructions on how to perform some of these tasks, or for more information on the functionality in question.

## CyberDrain Hosted Clients

{% stepper %}
{% step %}
### Active Sponsorship

Start by signing up for the €99/month subscription through our [secure checkout](https://pay.cyberdrain.com/b/4gM7sLa003Sldjn6nu6wE01).
{% endstep %}
{% endstepper %}

## Self-Hosted Clients

{% stepper %}
{% step %}
#### Microsoft Tenant Requirements

* **Multi-Tenant Mode**: A Microsoft Partner account with your clients’ tenants added.\
  If you’re an MSP managing multiple tenants, this is essential for CIPP to function across them.
* **Single Tenant Mode or Direct Adds:** When you are not a Microsoft Partner, but want to add multiple tenants, one tenant has to be designated as the tenant that hosts the Application registration CIPP connects with. We consider this the "Partner Tenant" going forward.
{% endstep %}

{% step %}
#### Azure Subscription

You’ll need an **active Azure Subscription** where your CIPP resources (Function Apps, Static Web Apps, Key Vault, etc.) will live. If you’re new to Azure, check out [Azure’s free trial](https://azure.microsoft.com/free/) or confirm your existing subscription’s permissions
{% endstep %}

{% step %}
#### Azure Expertise (Assumed)

For the installation and maintenance of CIPP, we assume you’re comfortable with:

* **Azure Web Apps**: [Learn more](https://learn.microsoft.com/azure/azure-functions/)
* **Azure Key Vault**: [Learn more](https://learn.microsoft.com/azure/key-vault/general/)
* **Azure Cost Management**: [Learn more](https://learn.microsoft.com/azure/cost-management-billing/)
* **Azure Storage** (Tables, Blobs, Files): [Learn more](https://learn.microsoft.com/azure/storage/)

{% hint style="warning" %}
The linked resources above will help you understand the Azure services CIPP depends on that you will be required to configure and maintain. If you’re missing any of these skills, we suggest reviewing these before proceeding. Proper knowledge ensures a smooth deployment and ongoing maintenance.

Failing to understand proper deployment and maintenance of an application deployed to Azure can lead to ballooning costs.
{% endhint %}
{% endstep %}
{% endstepper %}

***

{% hint style="info" %}
## **You’re Ready for Installation**

Once you’ve checked off these prerequisites, move on to the next page to set up your self-hosted instance. Happy CIPPing!
{% endhint %}

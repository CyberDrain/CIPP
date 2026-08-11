---
description: How to grant users access to the CIPP App
---

# Setting Up SSO and Getting Access to CIPP

## First Time SSO and First User Setup

When you first set up CIPP, you'll need to setup your instance to create your first user, and allow yourself access via SSO.

{% stepper %}
{% step %}
### Browse to your newly setup CIPP domain

For CyberDrain hosted clients, this is in the management portal or the email you receive when deployment is complete. For self-hosted clients, this will be found in the Azure Portal
{% endstep %}

{% step %}
### Enter a username for the superadmin

This must be a M365 user that is able to log on to your tenant.

{% hint style="info" %}
CyberDrain hosted clients do not need to manually complete this step. It is generated from the form you filled out on the management portal to start your deployment process. This section will be greyed out.
{% endhint %}
{% endstep %}

{% step %}
### Choose which type of logon you want to allow to CIPP

* Single tenant is the most secure, and the logons will be limited to the tenant you sign in with
* Multi-tenant is required if you have a separation between GDAP and normal usage tenant.
{% endstep %}

{% step %}
### Sign in

Sign in with a user that has Application Administrator permissions or higher, advanced users can use Setup 2B for manual setup of the SSO app.
{% endstep %}
{% endstepper %}

{% @storylane/embed subdomain="app" url="https://app.storylane.io/share/admss49amlvr" linkValue="admss49amlvr" %}

## Additional User Setup

Once you have your initial user added, this user can add more users through the CIPP interface under CIPP -> Advanced -> Authentication -> [cipp-users.md](../../user-documentation/cipp/advanced/authentication/cipp-users.md "mention").

## Built-In Roles

CIPP features a role management system which utilizes the [Roles feature of Azure Static Web Apps](https://learn.microsoft.com/en-us/azure/static-web-apps/authentication-authorization?tabs=invitations#roles). The roles available in CIPP are as follows:

| Role Name  | Description                                                                                                                                                                           |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| readonly   | Only allowed to read and list items and send push messages to users.                                                                                                                  |
| editor     | Allowed to perform everything, except change system settings and manage Standards.                                                                                                    |
| admin      | Allowed to perform everything.                                                                                                                                                        |
| superadmin | A role that is only allowed to access the settings menu for specific high-privilege settings, such as setting up the [owntenant.md](../installation/owntenant.md "mention") settings. |

You can assign these roles to Entra groups or users using the [cipp-roles](../../user-documentation/cipp/advanced/authentication/cipp-roles/ "mention") page, so you no longer have to add users manually.

## Custom Roles

{% hint style="info" %}
Not sure how built-in and custom roles combine when a user is in multiple Entra groups? See [how-cipp-evaluates-roles.md](../resources/how-cipp-evaluates-roles.md "mention") for the precedence for rules.
{% endhint %}

While CIPP only supplies the above roles by default, you can create your own custom roles and apply them to your users with `editor` or `readonly` rights, admin users are unaffected by custom roles.

{% hint style="info" %}
Custom role permissions can only grant the highest level of the base permission. You cannot grant edit permissions to the `readonly` role. Assigning the `editor` role and then using a custom role to remove permissions will provide you with the functionality you're looking for there.

In the same way, assigning multiple custom roles is restrictive and not additive. The user will only have the lowest granted permission included in the combined set. A missing permission in the set is implied as no permission.
{% endhint %}

Set up Custom Roles by following these steps:

{% stepper %}
{% step %}
### Open the CIPP Roles Page

Go to CIPP -> Advanced -> Authentication -> [cipp-roles](../../user-documentation/cipp/advanced/authentication/cipp-roles/ "mention").
{% endstep %}

{% step %}
### Select a Custom Role from the list or start typing to create a new one if you do not yet have any

{% hint style="info" %}
Please ensure that your custom role is entirely in lowercase and does not contain spaces or special characters.
{% endhint %}
{% endstep %}

{% step %}
### Entra ID Group Mapping

Optionally select a Entra group this role will be mapped to. Adding an Entra group removes the requirement to add the user to either the SWA or inviting via the Management Portal.
{% endstep %}

{% step %}
### Allowed Tenants

For Allowed Tenants select a subset of tenants to manage, tenant groups, or AllTenants.

{% hint style="info" %}
If AllTenants is selected, you can block a subset of tenants or tenant groups using Blocked Tenants.
{% endhint %}
{% endstep %}

{% step %}
### Endpoint Restrictions

Optionally select the CIPP endpoints that you want to block for the role. For example, if you do not want the role to have access to delete users/mailboxes you would block `RemoveUser`.
{% endstep %}

{% step %}
### API Permissions

Select the API permission from the listed categories and choose from None, Read or Read/Write.

* To find out which API endpoints are affected by these selections, click on the Info button.
* Not defining a category is the same as setting None. Be sure that you define all base role permissions you want to apply to the user.
{% endstep %}

{% step %}
### Base Role Assignment

You must be sure to assign both the custom role and the base role `readonly` or `editor` to the users.

* If using Entra ID groups, you can map the base role to a Entra group (eg. `CIPP readonly` mapped to `readonly`) and add the user to the base role Entra group and the custom role Entra group to properly manage permissions
* If using SWA role management (self-hosted) or management portal (CyberDrain hosted) be sure to add both roles to the user manually.
{% endstep %}
{% endstepper %}

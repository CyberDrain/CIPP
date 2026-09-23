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

CIPP features a role management system which utilises the [Roles feature of Azure Static Web Apps](https://learn.microsoft.com/en-us/azure/static-web-apps/authentication-authorization?tabs=invitations#roles). The roles available in CIPP are as follows:

| Role Name  | Description                                                                                                                                                                           |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| readonly   | Only allowed to read and list items and send push messages to users.                                                                                                                  |
| editor     | Allowed to perform everything, except change system settings and manage Standards.                                                                                                    |
| admin      | Allowed to perform everything.                                                                                                                                                        |
| superadmin | A role that is only allowed to access the settings menu for specific high-privilege settings, such as setting up the [owntenant.md](../installation/owntenant.md "mention") settings. |

You can assign these roles to Entra groups or users using the [cipp-roles](../../user-documentation/cipp/advanced/authentication/cipp-roles/ "mention") page, so you no longer have to add users manually.

## Legacy Self-Hosted (Static Web App) Role Management

Instances still running the earlier Function App and Static Web App architecture, from before the [migrating-to-the-new-infrastructure.md](../maintaining-cipp/migrating-to-the-new-infrastructure.md "mention") migration, invite users and assign built-in roles from the Static Web App resource rather than from an Entra group mapping.

{% stepper %}
{% step %}
### Go to the Azure Portal
{% endstep %}

{% step %}
### Go to your CIPP resource group
{% endstep %}

{% step %}
### Select your CIPP Static Web App, `CIPP-SWA-XXXX`
{% endstep %}

{% step %}
### Under Settings, select Role Management

Not IAM Role Management.
{% endstep %}

{% step %}
### Select Invite User and add the roles for the user

Multiple roles can be applied to the same user.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
After the invite link is sent to the user, they must click on it to accept the invite and gain access to the app. The invite expires after a set amount of time, and the link is not emailed to them automatically, so send it manually.
{% endhint %}

{% hint style="danger" %}
Roles added or changed this way can take a long time to propagate, up to 24 hours in some cases. Map CIPP roles to Entra ID groups instead wherever you can: permission changes made through a group membership apply in minutes rather than hours.
{% endhint %}

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

{% hint style="warning" %}
A handful of estate-wide operations are refused outright to a role that does not have unrestricted tenant access, meaning **Allowed Tenants** left as `AllTenants` with nothing in **Blocked Tenants**. These are adding a tenant through the Setup Wizard, creating, editing and deleting custom data mappings, saving an integration's tenant or field mapping, and creating, editing, deleting or re-running the rules of a tenant group. A restricted role can still open these pages, but is refused at the point it tries to save.
{% endhint %}
{% endstep %}

{% step %}
### Endpoint Restrictions

Optionally select the CIPP endpoints that you want to block for the role. For example, if you do not want the role to have access to delete users/mailboxes you would block `RemoveUser`.
{% endstep %}

{% step %}
### API Permissions

Custom roles define their permissions in one of two ways, chosen with the **Simple (patterns)** and **Advanced (per-category)** toggle. A new role opens in Simple mode, and a role you open for editing opens in Advanced mode.

**Simple (patterns)** works the way CIPP's built-in roles do. An **Include** list grants everything matching its patterns, an **Exclude** list then denies anything matching its own, and exclusions always win.

* Patterns match permission names in the form `Category.Object.Level`, where the level is `Read` or `ReadWrite`, and `*` matches anything. `Identity.*.Read` grants read access to everything under Identity, and `*` grants everything.
* A pattern holds up to three dot-separated segments of letters, numbers and `*`. Anything else is reported and dropped rather than saved.
* **Start from a built-in role** replaces both lists with that role's own patterns, which you are then free to edit.
* The **Live result** panel counts what each pattern matches and flags any pattern matching nothing, so a typo does not pass unnoticed.
* Patterns are expanded every time permissions are evaluated, so a role built on wildcards picks up endpoints added in later CIPP releases on its own.

**Advanced (per-category)** is the category list, where each category is set to None, Read or Read/Write.

* To find out which API endpoints are affected by these selections, click on the Info button.
* Not defining a category is the same as setting None. Be sure that you define all base role permissions you want to apply to the user.
* A role defined this way grants only the categories that existed when you saved it, so review it after a CIPP update. See [how-cipp-evaluates-roles.md](../resources/how-cipp-evaluates-roles.md "mention").

{% hint style="warning" %}
The two modes are not merged. Saving in Simple mode replaces the role's permissions with the patterns on screen, and CIPP warns you when the categories and the patterns have diverged.
{% endhint %}
{% endstep %}

{% step %}
### Base Role Assignment

You must be sure to assign both the custom role and the base role `readonly` or `editor` to the users.

* If using Entra ID groups, you can map the base role to a Entra group (eg. `CIPP readonly` mapped to `readonly`) and add the user to the base role Entra group and the custom role Entra group to properly manage permissions
* If using SWA role management (self-hosted) or management portal (CyberDrain hosted) be sure to add both roles to the user manually.
{% endstep %}
{% endstepper %}

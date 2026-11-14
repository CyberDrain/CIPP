# Add Group Template

This page creates a group template, which records the settings for a group so the same group can be created again later, in one tenant or across many. Complete the shared details, choose a group type, then fill in any additional settings that appear for that type. Templates are applied from the **Deploy Group Template** drawer, described on the [README.md](README.md "mention") page.

## Template Details

These fields apply to every group type.

| Field        | Description                                                          |
| ------------ | -------------------------------------------------------------------- |
| Display Name | The name the group is given when the template is applied. Required.  |
| Description  | The description the group is given when the template is applied.     |
| Username     | The mail nickname the group's email address is built from. Required. |

{% hint style="warning" %}
Username is the Microsoft 365 mail nickname, which has to be unique within a tenant. A template built from an existing group carries that group's nickname, so it needs overwriting before the template is used in the same tenant.
{% endhint %}

{% hint style="info" %}
Any field in a template accepts a variable, written as `%variablename%`, which is replaced with the target tenant's value when the template is applied. `%tenantfilter%` gives the tenant's default domain, as in `postmaster@%tenantfilter%`, and `%tenantname%` gives the tenant's name, so a **Display Name** of `%tenantname% Administrators` produces an appropriately named group in each tenant. Values for your own variables are set for every tenant in [global-variables.md](../../../tenant/administration/tenants/global-variables.md "mention"), or for one tenant in the Custom Variables box on [edit.md](../../../tenant/manage/edit.md "mention"), where the tenant's own value wins.
{% endhint %}

## Group Type

Select one group type. The type determines which additional settings appear below the selector.

| Group Type                  | Description                                                                                                     |
| --------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Azure Role Group            | A role-assignable security group, used to assign Entra ID directory roles to a group of users.                  |
| Security Group              | A standard security group, used for granting access to resources and for group-based licensing.                 |
| Microsoft 365 Group         | A Microsoft 365 (unified) group with a shared mailbox, calendar, and associated SharePoint site.                |
| Dynamic Group               | A security group whose membership is calculated automatically from a membership rule.                           |
| Distribution List           | An Exchange Online distribution group for delivering mail to a static list of recipients.                       |
| Mail Enabled Security Group | A security group that can also receive mail, allowing it to be used both for permissions and for mail delivery. |

## Additional Settings

These settings appear only for the group types listed against them.

| Setting                                             | Group Types                                    | Description                                                                                                                                                                                                                                                                                        |
| --------------------------------------------------- | ---------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Licenses (optional)                                 | Security Group                                 | Licences assigned to the group, so members inherit them through group-based licensing. Group-based licensing requires the tenant to be licensed for Entra ID P1 or higher. Assigning licences through a group without the appropriate licensing is not compliant with Microsoft's licensing terms. |
| Let people outside the organization email the group | Distribution List                              | Allows senders outside the organisation to email the group. When left off, only authenticated internal senders can deliver to it.                                                                                                                                                                  |
| Email Aliases                                       | Distribution List, Mail Enabled Security Group | Additional email addresses for the group, entered one per line. Added as secondary addresses alongside the primary address.                                                                                                                                                                        |
| Hide this group from the Global Address List (GAL)  | Distribution List, Mail Enabled Security Group | Hides the group from address lists, so it does not appear when users browse or search for recipients.                                                                                                                                                                                              |
| Dynamic Group Parameters                            | Dynamic Group                                  | The rule that determines membership, written in Entra ID membership rule syntax.                                                                                                                                                                                                                  |

{% hint style="info" %}
An example membership rule for a dynamic group, excluding guests and external users:

`(user.userPrincipalName -notContains "#EXT#@") -and (user.userType -ne "Guest")`
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

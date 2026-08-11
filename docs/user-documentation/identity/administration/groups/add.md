# Add Group

This page creates a new group in the selected tenant. Complete the shared details, choose a group type, then fill in any additional settings that appear for that type. Selecting **Submit** creates the group immediately, with no confirmation step.

## Group Details

These fields apply to every group type.

| Field               | Description                                                                                                                                                          |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name        | The name shown for the group in the Microsoft 365 admin center, address lists, and CIPP.                                                                             |
| Description         | A free-text description of the group's purpose.                                                                                                                      |
| Username            | The mail nickname for the group, entered without a domain. Combined with the primary domain to form the group's email address for group types that are mail-enabled. |
| Primary Domain name | The verified domain used for the group's email address. Only verified domains for the tenant are listed, and the tenant's default domain is selected automatically.  |
| Owners              | One or more users who will be able to manage the group.                                                                                                              |
| Members             | One or more users to add to the group when it is created.                                                                                                            |

{% hint style="info" %}
Security groups and Azure role groups are not mail-enabled, so **Username** and **Primary Domain name** are not used for those types. A random mail nickname is generated instead. Any characters other than letters, numbers, hyphens and underscores are stripped from the username before it becomes the mail nickname.
{% endhint %}

## Group Type

Select one group type. The type determines which additional settings appear below the selector.

| Group Type                  | Description                                                                                                                                         |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Azure Role Group            | A role-assignable security group, used to assign Entra ID directory roles to a group of users. Role assignability cannot be enabled after creation. |
| Security Group              | A standard security group, used for granting access to resources and for group-based licensing.                                                     |
| Microsoft 365 Group         | A Microsoft 365 (unified) group with a shared mailbox, calendar, and associated SharePoint site.                                                    |
| Dynamic Group               | A security group whose membership is calculated automatically from a membership rule.                                                               |
| Dynamic Distribution Group  | An Exchange Online distribution group whose membership is resolved at send time from a recipient filter.                                            |
| Distribution List           | An Exchange Online distribution group for delivering mail to a static list of recipients.                                                           |
| Mail Enabled Security Group | A security group that can also receive mail, allowing it to be used both for permissions and for mail delivery.                                     |

## Additional Settings

These settings appear only for the group types listed against them.

| Setting                                                         | Group Types                                                          | Description                                                                                                                                                            |
| --------------------------------------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Disable group nesting (prevent other groups from being members) | Azure Role Group, Security Group, Microsoft 365 Group, Dynamic Group | Prevents other groups from being added as members, so the group can only contain users.                                                                                |
| Licenses (optional)                                             | Security Group                                                       | Assigns one or more licenses to the group, so members inherit them through group-based licensing. Each license is listed with the number of units currently available. |
| Let people outside the organization email the group             | Distribution List, Dynamic Distribution Group                        | Allows senders outside the organization to email the group. When left off, only authenticated internal senders can deliver to it.                                      |
| Email Aliases                                                   | Distribution List, Mail Enabled Security Group                       | Additional email addresses for the group, entered one per line as full SMTP addresses. These are added as secondary addresses alongside the primary address.           |
| Hide this group from the Global Address List (GAL)              | Distribution List, Mail Enabled Security Group                       | Hides the group from address lists, so it does not appear when users browse or search for recipients.                                                                  |
| Subscribe members to receive group emails                       | Microsoft 365 Group                                                  | Automatically subscribes new members to the group's conversations, so group mail is delivered to their own inbox as well as the group mailbox.                         |
| Dynamic Group Parameters                                        | Dynamic Group, Dynamic Distribution Group                            | The rule that determines membership. Dynamic groups use Entra ID membership rule syntax; dynamic distribution groups use an Exchange Online recipient filter.          |

{% hint style="info" %}
An example membership rule for a dynamic group, excluding guests and external users:

`(user.userPrincipalName -notContains "#EXT#@") -and (user.userType -ne "Guest")`
{% endhint %}

{% hint style="warning" %}
Members entered on this page are ignored for a **Dynamic Group**, because membership is calculated from the rule rather than assigned directly. Owners are still applied.

A **Dynamic Distribution Group** goes further and ignores owners, members and the description as well. Only the display name, the recipient filter, the email address and the external sender setting are used at creation, so anything else needed on the group has to be set afterwards from the edit.md page or Exchange Online.
{% endhint %}

{% hint style="warning" %}
Group-based licensing requires the tenant to be licensed for Entra ID P1 or higher. Assigning licenses through a group without the appropriate licensing is not compliant with Microsoft's licensing terms.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

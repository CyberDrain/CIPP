---
description: Streamline group creation across multiple tenants in Microsoft 365
---

# Deploy Group Templates

The **Deploy Group Template** button on the [.](./ "mention") page and the [groups](../groups/ "mention") page opens a drawer that applies a saved group template to one or more tenants, creating the same group in each. The values a template supplies can be adjusted for this deployment without changing the stored template.

### Select Tenants

Choose the tenants the group should be created in. Several can be selected, and the group is created separately in each. There is no All Tenants option here, so the tenants have to be picked individually.

### Choose a Template

**Choose a Template** lists the saved templates by name and group type. Selecting one fills in the fields below, which can then be edited for this deployment. A template is not required: the fields can be completed by hand instead.

| Field                                              | Description                                                                                                                                                                                                               |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Group Type                                         | The kind of group to create: Dynamic Group, Security Group, Distribution Group, Azure Role Group or Mail Enabled Security Group. Required, and it decides which of the settings below appear. |
| Group Display Name                                 | The name the group is created with. Required.                                                                                                                                                                             |
| Group Description                                  | A description for the group.                                                                                                                                                                                              |
| Group Username                                     | The mail nickname the group's email address is built from.                                                                                                                                                                |
| Allow external emails to the group                 | Allows senders outside the organisation to email the group. Shown for a Distribution Group.                                                                                                                               |
| Membership Rules                                   | The rule that decides membership. Shown for a Dynamic Group, and required.                                                                                                                                                |
| Email Aliases                                      | Additional email addresses, one per line. Shown for a Distribution Group or Mail Enabled Security Group.                                                                                                                  |
| Hide this group from the Global Address List (GAL) | Hides the group from address lists. Shown for a Distribution Group or Mail Enabled Security Group.                                                                                                                        |

### Deploy

**Deploy Template** stays disabled until a tenant, a group type and a display name are set. The group is created in every selected tenant and the result is shown in the drawer, which can then be used again for another deployment.

{% hint style="info" %}
Any of the fields above accepts a variable, written as `%variablename%`, which is replaced with each target tenant's value as the group is created. `%tenantfilter%` gives the tenant's default domain, as in `postmaster@%tenantfilter%`, and `%tenantname%` gives the tenant's name, so one deployment can give every tenant a correctly named group. Values for your own variables are set for every tenant in [global-variables.md](../../../tenant/administration/tenants/global-variables.md "mention"), or for one tenant in the Custom Variables box on [edit.md](../../../tenant/manage/edit.md "mention"), where the tenant's own value wins.
{% endhint %}

{% hint style="info" %}
Licences held on a template are carried into the deployment even though the drawer does not display them, so a Security Group template with group-based licensing attached still assigns those licences. To see or change which licences a template holds, edit the template itself.
{% endhint %}

{% hint style="warning" %}
The Group Type list here does not include Microsoft 365 Group, so a Microsoft 365 template cannot be deployed from this drawer. Selecting one leaves the group type unset and Deploy Template stays disabled. Create Microsoft 365 groups from the [add.md](../groups/add.md "mention") page in the meantime.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

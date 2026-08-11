---
description: Streamline group creation across multiple tenants in Microsoft 365
---

# Deploy Group Templates

This wizard applies a saved group template to one or more tenants, creating the same group in each. Templates are managed on the [.](./ "mention") page, and the values a template supplies can be adjusted for this deployment without changing the stored template.

{% stepper %}
{% step %}
### Tenant Selection

Choose the tenants the group should be created in. Several can be selected, and the group is created separately in each. There is no All Tenants option here, so the tenants have to be picked individually.
{% endstep %}

{% step %}
### Choose Template

**Choose a Template** lists the saved templates by name and group type. Selecting one fills in the fields below, which can then be edited for this deployment. A template is not required: the fields can be completed by hand instead.

| Field                                              | Description                                                                                                                                                                                                               |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Group Type                                         | The kind of group to create: Dynamic Group, Dynamic Distribution Group, Security Group, Distribution Group, Azure Role Group or Mail Enabled Security Group. Required, and it decides which of the settings below appear. |
| Group Display Name                                 | The name the group is created with. Required.                                                                                                                                                                             |
| Group Description                                  | A description for the group.                                                                                                                                                                                              |
| Group Username                                     | The mail nickname the group's email address is built from.                                                                                                                                                                |
| Allow external emails to the group                 | Allows senders outside the organization to email the group. Shown for a Distribution Group.                                                                                                                               |
| Membership Rules                                   | The rule that decides membership. Shown for a Dynamic Group or Dynamic Distribution Group, and required for both.                                                                                                         |
| Email Aliases                                      | Additional email addresses, one per line. Shown for a Distribution Group or Mail Enabled Security Group.                                                                                                                  |
| Hide this group from the Global Address List (GAL) | Hides the group from address lists. Shown for a Distribution Group or Mail Enabled Security Group.                                                                                                                        |
{% endstep %}

{% step %}
### Confirmation

Review the values and submit. The group is created in every tenant selected in the first step.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
**Group Username** and **Email Aliases** accept variables, so one template can produce tenant-appropriate addresses across a multi-tenant deployment. `%tenantfilter%` is replaced with the target tenant's domain, as in `postmaster@%tenantfilter%`.
{% endhint %}

{% hint style="info" %}
Licenses held on a template are carried into the deployment even though this wizard does not display them, so a Security Group template with group-based licensing attached still assigns those licenses. To see or change which licenses a template holds, edit the template itself.
{% endhint %}

{% hint style="warning" %}
The Group Type list here does not include Microsoft 365 Group, so a Microsoft 365 template cannot be deployed from this wizard. Selecting one leaves the group type unset and the wizard will not continue. Create Microsoft 365 groups from the [add.md](../groups/add.md "mention") page in the meantime.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

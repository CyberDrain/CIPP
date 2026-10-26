# Start Tenant Onboarding

This page starts the onboarding process for a tenant. Select a GDAP relationship, confirm the roles it will be mapped with, and start the run. Progress is shown live alongside the form, so you can watch each step complete or see where it failed.

You will arrive here either from the **Start Tenant Onboarding** button, from the **Start Onboarding** action on a relationship, or by opening the Onboarding Url recorded against an invite. In the latter two cases the relationship is already selected for you.

## Relationship

| Field                       | Description                                                                                                                                                                         |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Select GDAP Relationship    | The relationship to onboard. Only active and approval pending relationships are offered, and Microsoft-Led Transition relationships are excluded. Required.                         |
| Assign a GDAP Role Template | The role template to map the relationship with. Only shown when the relationship has no pending invite, since an invite already carries its own role mappings. Required when shown. |

Once a relationship is selected, CIPP compares the roles it grants against the roles in the invite or template and reports one of the following.

| Result                                  | Description                                                                                 |
| --------------------------------------- | ------------------------------------------------------------------------------------------- |
| All roles are mapped correctly          | The relationship and the mappings agree, and onboarding can proceed.                        |
| Roles not available in the relationship | Roles in the template are absent from the relationship, so they cannot be mapped.           |
| Roles not mapped with the template      | The relationship grants roles the template does not cover, so they will be left unassigned. |

## Options

| Setting                                           | Description                                                                                                                          |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Ignore Missing Default Roles                      | Allows onboarding to continue when the relationship does not contain all of CIPP's default roles. Only shown when roles are missing. |
| Exclude onboarded tenant from top-level standards | Prevents the tenant from picking up standards that are applied to all tenants.                                                       |
| Add onboarded tenant to Tenant Groups             | The [tenant groups](../../administration/tenants/groups/README.md) to add the tenant to. You can choose several. Only static groups are offered, since dynamic groups work out their own membership. The tenant is added once its CPV permissions have been refreshed, and each group it joins is recorded in the onboarding logs. Optional. |

{% hint style="warning" %}
Onboarding will fail if the relationship is missing any of the default roles, unless **Ignore Missing Default Roles** is enabled. Be aware that CIPP may not function correctly against the tenant if this is the only relationship you hold with it.
{% endhint %}

## Current Relationship Details

A summary of the selected relationship, shown so you can confirm you have the right one before starting.

| Field                | Description                                                                                  |
| -------------------- | -------------------------------------------------------------------------------------------- |
| Customer             | The customer tenant, or `Pending Invite` where the invite has not yet been accepted.         |
| Status               | The current state of the relationship.                                                       |
| Auto Extend Duration | How long the relationship extends by on renewal, or a note that it is not eligible.          |
| Pending Invite       | Whether a CIPP invite is still outstanding for this relationship.                            |
| Created Date         | When the relationship was created.                                                           |
| Last Modified Date   | When the relationship was last changed.                                                      |
| Invite URL           | The link for a Global Administrator in the customer tenant to approve the relationship.      |
| Access Details       | The roles the relationship grants, or the invite's role mappings where an invite is pending. |

## Onboarding Status

Once started, the run appears alongside the form with its overall status, the time it was last updated, and the five onboarding steps. Failed steps are marked, and the logs can be opened for the detail behind them.

**Start** runs the onboarding. It is unavailable while a run is queued or in progress, and once a run has finished. **Retry** appears after a run exists and repeats it, which is the route back after a failure.

{% hint style="info" %}
The status panel polls every few seconds while a run is active, so it updates without reloading the page.
{% endhint %}

{% hint style="danger" %}
The Global Administrator role is a highly privileged role that should be used with caution. GDAP Relationships with this role will not be eligible for auto-extend.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

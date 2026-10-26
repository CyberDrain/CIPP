# Template Library

A template library keeps CIPP's stored templates in step with an external source. Point it at one of your tenants and CIPP copies that tenant's live policies into templates on a schedule, so you always hold a current copy. Point it at a community repository and CIPP pulls the templates published there whenever new versions are released.

Tenant-based libraries sync every 4 hours. Community repository libraries sync every 7 days.

This page needs the `CIPP.TemplateLibrary` permission together with the Scheduler permission that runs the sync.

{% hint style="warning" %}
Enabling this feature will overwrite templates with the same name.
{% endhint %}

## Choosing a Source

A library draws from either a tenant or a community repository, not both. Select one or the other from the two fields at the top of the page.

### Tenant

Choose a tenant to use as the source. CIPP reads its live policies and turns each one into a template.

{% hint style="success" %}
CIPP recommends using a Customer Development Experience tenant for developing your templates. See Microsoft's [CDX documentation](https://cdx.transform.microsoft.com/) for more information.
{% endhint %}

### Community Repository

Choose a repository registered with your instance. Once selected, a **Repository Branch** section appears with a **Select Branch** field, prefilled with the repository's default branch and changeable if the templates you want live elsewhere.

Repositories are managed on the [README.md](community-repos/README.md "mention") page, where you can register your own alongside the built-in ones. CIPP ships with five repositories registered:

| Repository                                                                         | Contents                                                                                        |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| [CIPP Templates](https://github.com/CyberDrain/CIPP-Templates)                     | CyberDrain's own repository, covering standards, groups, policies, Conditional Access and more. |
| [CyberDrain CIS Templates](https://github.com/CyberDrain/CyberDrain-CIS-Templates) | Intune templates aligned to CIS benchmarks.                                                     |
| [Open Intune Baseline](https://github.com/SkipToTheEndpoint/OpenIntuneBaseline)    | A widely used Intune device baseline applying multiple frameworks including CIS and NIS.        |
| [Conditional Access Baseline](https://github.com/j0eyv/ConditionalAccessBaseline)  | A ready-made framework of Conditional Access templates.                                         |
| [Intune Baselines](https://github.com/IntuneAdmin/IntuneBaselines)                 | A further set of Intune baseline templates.                                                     |

{% hint style="info" %}
A repository-based library imports every template file the selected branch contains. The template type switches below apply to tenant-based libraries.
{% endhint %}

## Template Types

Which switches appear depends on the source selected.

For a tenant, choose the policy types to copy:

| Setting                               | Description                                                                                     |
| ------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Create Conditional Access Templates   | Copies the tenant's Conditional Access policies, resolving the users and groups they reference. |
| Create Intune Configuration Templates | Copies the tenant's device configuration profiles.                                              |
| Create Intune Compliance Templates    | Copies the tenant's compliance policies.                                                        |
| Create Intune Protection Templates    | Copies the tenant's app protection policies.                                                    |

For the CyberDrain CIPP Templates repository, a different set is offered covering the template kinds that repository publishes:

| Setting                   | Description                   |
| ------------------------- | ----------------------------- |
| Create Template Standards | Standards templates.          |
| Create Group Templates    | Group templates.              |
| Create Policy Templates   | Policy templates.             |
| Create CA Templates       | Conditional Access templates. |

## Setting Up a Template Library

{% stepper %}
{% step %}
### Select a tenant or a community repository

Choose the source the templates will come from. Selecting a repository also lets you pick a branch. Until one or the other is chosen, the page says so and **Submit** stays greyed out. Choosing a source that already has a library raises a warning naming it, so you can go and edit that one instead of having the save rejected.
{% endstep %}

{% step %}
### Select template types

Toggle on the template types you would like copied.
{% endstep %}

{% step %}
### Submit

Saving creates a scheduled task named after the tenant or repository, which performs the sync from then on. A source that already has a library is rejected as a duplicate, so each tenant and each repository can only have one. A tenant library syncs every four hours, a repository library every seven days.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
Templates are compared before being written. Where a template already exists, carries the same source, and its content is unchanged, CIPP skips it rather than rewriting it, so a sync that reports no changes is working correctly.
{% endhint %}

## Configured Template Libraries

A table at the foot of the page lists every template library already set up, across all tenants and repositories rather than only the tenant currently selected. It refreshes itself when you create a new one.

| Column        | Description                                                                          |
| ------------- | ------------------------------------------------------------------------------------ |
| Name          | The name of the library, taken from the tenant or the repository it was created for. |
| Tenant        | The tenant the library writes into, or **No tenant** for a repository library.       |
| Recurrence    | How often the library syncs.                                                         |
| Task State    | Where the sync has got to, for example planned, running or completed.                |
| Executed Time | When the library last ran.                                                           |
| Results       | What the last run reported.                                                          |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Delete Library</td><td>Stops the library syncing after you confirm. Templates the library has already imported stay in CIPP and are not imported again; delete those separately from the Conditional Access or Intune template pages if you no longer need them. Greyed out unless you have write access to the scheduler.</td><td>true</td></tr></tbody></table>

To change how a library runs rather than remove it, use [README.md](scheduler/README.md "mention"). Community repository libraries appear there with the tenant filter set to All Tenants.

{% include "../../../.gitbook/includes/feature-request.md" %}

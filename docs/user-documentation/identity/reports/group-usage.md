# Group Usage Report

This report lists every group in the selected tenant together with where it is actually used — Conditional Access policies, Intune assignments, role assignments, application assignments, group-based licensing and transport rules. Groups nothing references are marked as unused, which makes this the quickest way to find groups that can be cleaned up, and to check what would break before removing one.

## Filters

| Filter                     | Shows                                                                    |
| -------------------------- | ------------------------------------------------------------------------ |
| Unused groups              | Groups that nothing currently references, so are candidates for cleanup. |
| Used in Conditional Access | Groups referenced by at least one Conditional Access policy.             |
| Used in Intune             | Groups referenced by at least one Intune assignment.                     |
| Used for licensing         | Groups used to assign licences through group-based licensing.            |

## Table Details

The table is served from the CIPP reporting database cache rather than live Graph calls, so it loads instantly. **Used Locations** names the systems that reference the group, **Used In** lists the specific policies or assignments, and **Usage Count** totals them; **Is Used** rolls that up to a simple Yes/No.

The filter menu ships with shortcuts for the common questions: unused groups, groups used in Conditional Access, groups used in Intune, and groups used for licensing.

## Refreshing the data

Because the report reads from cache, changes in the tenant appear after the next sync. The sync button on the page refreshes every data source the report depends on (groups, Conditional Access, Intune, roles, applications, licenses, transport rules); this can take a few minutes for larger tenants.

{% include "../../../../.gitbook/includes/feature-request.md" %}

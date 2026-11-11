# Controls

The Controls tab compares each Secure Score recommendation across every tenant, to show which recommendations the estate as a whole is weakest on. It is only listed while All Tenants is selected, since there is nothing to compare for a single tenant. Like the other All Tenants views it is drawn from CIPP's nightly score cache rather than live calls to Microsoft.

## Table Details

Each row is one recommendation, sorted lowest average first.

| Column          | Description                                                                                                        |
| --------------- | ------------------------------------------------------------------------------------------------------------------ |
| Control Name    | Microsoft's identifier for the recommendation. Selecting it opens the Table tab filtered to that recommendation.   |
| Title           | The name of the recommendation.                                                                                    |
| Tier            | Core, Defense in Depth, or Advanced.                                                                               |
| Reporting       | How many tenants report the recommendation at all.                                                                 |
| Complete        | Tenants at 100%.                                                                                                   |
| Partial         | Tenants part of the way there.                                                                                     |
| Not Started     | Tenants at 0%.                                                                                                     |
| No Data         | Tenants in view that do not report the recommendation, typically because their licensing does not include it.     |
| Average Percent | The average completion across the tenants that report a score for it.                                              |
| Spread          | A bar split into complete (green), partial (amber) and not started (red); the unfilled remainder is no data.       |

The tier presets narrow the list, and the **Tenant groups** picker recalculates every count for the tenants in any of the ticked CIPP tenant groups. **Show tenants** in the row menu does the same as selecting the control name.

{% hint style="info" %}
Recommendations a tenant has marked as resolved by a third party or as risk accepted count with the score Microsoft reports for them, the same as in Microsoft's own reporting.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

# Applied Standards Report

The Applied Standards Report shows, for a single tenant, every standard in a chosen template alongside the tenant's current configuration, so you can see at a glance which standards the tenant meets and where it falls short. Each standard is presented with the configuration the template expects and the value found in the tenant. The page is titled after the template being reported on.

## Page Actions

| Action           | Description                                                                                                           |
| ---------------- | --------------------------------------------------------------------------------------------------------------------- |
| Refresh Data     | Reloads the comparison results and the template details.                                                              |
| Edit Template    | Opens the template in the template editor.                                                                            |
| Run Standard Now | Forces an immediate run of the standard rather than waiting for its schedule. You choose which tenant to run against. |

## Selecting a Template

A **Template** selector at the top of the page chooses which standards template to report on, and a search box narrows the standards shown to those matching the text entered. A **Logs** button opens the log entries recorded for this standard against the current tenant.

## Filters

A filter menu restricts which standards are listed. Each option shows a count.

| Filter                            | Shows                                                                                                       |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| All                               | Every standard in the template.                                                                             |
| Compliant                         | Standards where the tenant matches what the template expects.                                               |
| Non-Compliant                     | Standards where the tenant does not match.                                                                  |
| Overridden                        | Standards whose value has been overridden for this tenant.                                                  |
| Accepted Deviations               | Standards with a deviation that has been accepted. Shown for drift templates that have accepted deviations. |
| Non-Compliant (License available) | Non-compliant standards that the tenant is licensed for, and which can therefore be acted on.               |

## Standards

Standards are grouped under their category headings, each shown as a card pairing the **Expected Configuration** from the template with the value found in the tenant. Where a configuration has several properties, they are broken out one by one so it is clear which part differs. Each standard is marked Compliant or Non-Compliant, and where the tenant is not licensed for a standard, a notice explains that the required licenses are missing rather than reporting a failure.

Labels on each card identify what is being shown and how the standard runs:

| Label          | Meaning                                                                |
| -------------- | ---------------------------------------------------------------------- |
| Standard       | The configuration the standard defines.                                |
| Template       | The value as set in the template.                                      |
| Current Tenant | The value as found in the tenant.                                      |
| Auto-Remediate | The standard corrects the tenant automatically when it does not match. |
| Run Manually   | The standard only reports, and is applied when run by hand.            |

## Comparing to the Baseline

Standards based on an Intune template carry a **Compare** button, which opens a comparison of the template baseline against the policy as it exists in the tenant.

| Element             | Description                                                                                                                              |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Not deployed notice | Shown where the policy does not exist in the tenant at all, naming the policy that is missing.                                           |
| Summary             | States whether the two are identical, or how many differences were found.                                                                |
| Differences table   | Lists each differing property with its Baseline and Tenant values, and whether the values differ or the setting exists on only one side. |
| Full settings       | The complete configuration of both the baseline and the tenant policy.                                                                   |

## Run Standard Report

A **Run Standard Report** option regenerates the comparison data for the selected template, refreshing the results shown on the page.

## Known Issues

* There is currently a limitation with Conditional Access standards due to the complexity of the comparison the standard settings and the Conditional Access response object. We hope to resolve this in a future update.

{% include "../../../../.gitbook/includes/feature-request.md" %}

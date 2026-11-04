# Remediations

The Remediations tab of the [View Device](README.md) page lists the Intune remediation scripts that have run on the device, with the result of each detection and remediation pass and the output each script reported. Use it to see whether a remediation found and fixed a problem on this device, and to run one again without waiting for its next scheduled run.

The page header and the device actions are the same as on the device's Overview tab. To run a remediation script that has not yet run on the device, use **Run Remediation Script** from the device actions.

## Table Details

The properties returned are for the Graph resource type `deviceHealthScriptPolicyState`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/graph/api/resources/intune-devices-devicehealthscriptpolicystate?view=graph-rest-beta).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Run Again</td><td>Asks the device to run the selected remediation script again straight away, after confirmation. The new result appears here once the device reports back.</td><td>true</td></tr></tbody></table>

{% include "../../../../../../.gitbook/includes/feature-request.md" %}

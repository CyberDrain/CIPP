# Features

Feature flags control the visibility of parts of CIPP that are either still in preview or on their way out. Disabling a flag hides the relevant pages, disables the API endpoints behind them, and stops any scheduled timers the feature uses, so it is a genuine switch rather than a cosmetic one.

To change a flag, open the actions menu on its row and choose **Enable Feature** or **Disable Feature**. Multiple flags can be changed at once by selecting their checkboxes and using the bulk actions dropdown.

### Current Feature Flags

| Feature                | Status      | Description                                                                                                                                                      |
| ---------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Best Practice Analyzer | Deprecation | This feature is being deprecated in favor of the new reporting database cache being used by Dashboard v2 and will be removed in a future release.               |
| MCP Server             | Beta        | Model Context Protocol (MCP) server endpoint that exposes CIPP's read-only API surface as tools for AI clients. Disabled by default; enable to allow MCP access. |

{% hint style="info" %}
CIPP maintains further internal flags that are not shown on this page. Those govern behavior determined by how your instance is hosted rather than by preference, so they are set automatically and cannot be toggled.
{% endhint %}

## Table Details

| Column      | Description                                         |
| ----------- | --------------------------------------------------- |
| Name        | The name of the feature the flag controls.          |
| Enabled     | Whether the feature is currently switched on.       |
| Description | What the feature does, and why it is behind a flag. |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Enable Feature</td><td>Switches the feature on, restoring its pages, endpoints and any scheduled timers it uses. Only offered for features that are currently disabled.</td><td>true</td></tr><tr><td>Disable Feature</td><td>Switches the feature off, hiding its pages and disabling its endpoints and timers. Only offered for features that are currently enabled.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
The Extended Info flyout lists exactly what a flag governs, namely the pages it shows, the API endpoints it enables, and any scheduled timers it controls. Check it before disabling a feature, so you know what stops working.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

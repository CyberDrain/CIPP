# Features

Feature flags control the visibility of parts of CIPP that are either still in preview or on their way out. Disabling a flag hides the relevant pages, disables the API endpoints behind them, and stops any scheduled timers the feature uses, so it is a genuine switch rather than a cosmetic one.

To change a flag, open the actions menu on its row and choose **Enable Feature** or **Disable Feature**. Multiple flags can be changed at once by selecting their checkboxes and using the bulk actions dropdown.

### Current Feature Flags

| Feature                | Status      | Description                                                                                                                                                      |
| ---------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| MCP Server             | Beta        | Model Context Protocol (MCP) server endpoint that exposes CIPP's read-only API surface as tools for AI clients. Disabled by default; enable to allow MCP access. |
| Baselines              | Opt-in      | The baseline engine that replaces classic Standards and Drift. Enabling it shows the [Baselines](../../tenant/baselines/README.md) pages, hides the classic Standards and Drift pages, and stops their scheduled runs, so the two never run side by side. Enabled by default on installs that have no classic Standards templates; disabled by default everywhere else. |
| Security Simulations   | Beta        | Plays realistic attacks against a tenant to show what an attacker would experience today and which controls close each gap. Enabling it shows the [Security Simulations](../../tenant/security-simulator/README.md) pages. Enabled by default on installs that have no classic Standards templates; disabled by default everywhere else. |

{% hint style="info" %}
A default only applies until you change the flag yourself. If your install has no classic Standards templates when the flag is first set up, Baselines and Security Simulations are switched on for you, because there is nothing for Baselines to replace. An install that already has Standards templates keeps them until you enable Baselines yourself. Either way, your own choice on this page is kept across upgrades.
{% endhint %}

{% hint style="info" %}
CIPP maintains further internal flags that are not shown on this page. Those govern behaviour determined by how your instance is hosted rather than by preference, so they are set automatically and cannot be toggled.
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

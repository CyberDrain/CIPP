# Edit Traffic Profile

Edits a traffic forwarding profile in the selected tenant. Open it with **Edit Profile** on the Traffic Forwarding page. Changes are written to the tenant when you save, and only the parts that differ from the tenant are changed. Results are listed for each change.

Changes take about 10 seconds to show in the tenant, so reloading straight away can show the old values.

## Fields

| Field                     | Description                                                                                                                     |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Enabled                   | Whether the profile is enabled.                                                                                                 |
| Assign to all users       | Applies the profile to every user. Turn it off to apply it only to the users and groups below.                                  |
| Assigned users and groups | Shown when **Assign to all users** is off. The exact users and groups the profile applies to: anyone you remove is unassigned. |
| Remote networks           | Microsoft 365 and Internet Access profiles only. The exact branch sites that send their traffic through this profile.           |

A remote network can only be added to an enabled profile, and each remote network keeps at least one profile, so a change that would leave a site with none is refused.

## Internet Access custom rules

Shown for the Internet Access profile only.

| Field                       | Description                                                                                     |
| --------------------------- | ----------------------------------------------------------------------------------------------- |
| Custom bypass destinations  | Destinations that skip Global Secure Access and go straight to the internet.                    |
| Custom acquire destinations | Destinations that are always sent through Global Secure Access.                                 |
| Ports                       | One list per section, for example `443` or `8000-8100`, comma separated. Blank means all ports. |

Destinations are FQDNs (`*.contoso.com` allowed), IPv4 addresses, subnets (`10.0.0.0/8`) or ranges (`10.0.0.1-10.0.0.9`). A section is only written when you change it. CIPP then replaces all of that section's rules with the entered destinations, for TCP and UDP on the entered ports.

If a section's existing rules use different ports for different destinations, its ports field starts blank. Changing that section applies one port list to all its destinations.

If part of the profile could not be read, its fields are hidden and that part is left unchanged.

{% include "../../../../../.gitbook/includes/feature-request.md" %}

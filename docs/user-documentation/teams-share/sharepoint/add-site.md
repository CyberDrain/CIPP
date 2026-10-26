# Add Site

Creates a single new SharePoint site in the selected tenant. Every field shown is required except **Public group**.

## SharePoint Site

| Field                | Description                                                                                                                                                                     |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Site Name            | The display name of the new site. The site URL (`/sites/<name>`) and, for group-connected sites, the group alias are derived from it by removing spaces and special characters. |
| Site Description     | The description of the new site.                                                                                                                                                |
| Add Owner            | The user who will own the site. The list shows the enabled users in the tenant.                                                                                                 |
| Template Name        | The kind of site to create: **Team (No Microsoft365 Group)**, **Team (Microsoft 365 Group)** or **Communication**.                                                              |
| Site Design Template | The site design to apply when the site is created: **Blank**, **Showcase** or **Topic**. Not shown for **Team (Microsoft 365 Group)**, which has no site design.                |
| Public group         | Only shown for **Team (Microsoft 365 Group)**. Turn on to create the Microsoft 365 group as public; off creates a private group.                                                |

**Team (Microsoft 365 Group)** creates a new Microsoft 365 group with the selected owner as its only owner; SharePoint then provisions the connected team site. The group's mail alias is derived from the site name. Provisioning can take a little while: if the site is not ready when the page reports success, the result names the group and the site appears shortly after. Group-connected sites use the tenant's default SharePoint language, whereas the other two templates are created in English.

{% include "../../../../.gitbook/includes/feature-request.md" %}

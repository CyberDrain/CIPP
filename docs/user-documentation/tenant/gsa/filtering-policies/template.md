# Add or Edit Filtering Policy Template

Creates a new filtering policy template, or edits an existing one.

## Fields

| Field               | Description                                                                                                      |
| ------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Name                | Required. Used as the policy name in every tenant the template is deployed to, so it must be unique in CIPP.     |
| When a rule matches | **Block** or **Allow** the traffic that matches any rule in the policy.                                          |
| Description         | Optional. Saved with the template and written to the policy in each tenant.                                      |

## Rules

A template needs at least one rule. Use **Add rule** for more, and the bin icon to remove one. Each rule has a name and matches on one of:

| Match on       | What to enter                                                                                     |
| -------------- | ------------------------------------------------------------------------------------------------- |
| Web categories | Pick one or more categories from the list, grouped as Microsoft groups them.                      |
| Domains (FQDN) | Type a domain and choose **Add option**, for example `contoso.com` or `*.contoso.com`.            |
| URLs           | Type a URL and choose **Add option**, for example `www.contoso.com/downloads/*`.                  |

Rule names must be unique within the template. If a deploy finds a web category the tenant does not offer, it stops before changing anything and names the category.

{% include "../../../../../.gitbook/includes/feature-request.md" %}

# Create Safe Links Template

Builds a new Safe Links policy template from scratch. The form is the same one used to create a live policy, but nothing is written to a tenant: the settings are saved in CIPP for deploying later with [add.md](add.md "mention").

## Template Information

| Field | Description |
| ----- | ----------- |
| Template Name | Required. Names the template. It is checked against your existing templates as you type, and a name already in use is rejected. |
| Template Description | Describe what this template is used for. |

## Safe Links Policy Configuration

**Policy Settings**

| Field | Description |
| ----- | ----------- |
| Policy Name | Required. The name the policy will be created with in each tenant you deploy to. It is checked against the currently selected tenant's existing policies, and a name already in use there is rejected. |
| Description | Free text describing what the policy is for. |
| Enable Safe Links For Email | Protects links in email. |
| Enable Safe Links For Teams | Protects links in Teams. |
| Enable Safe Links For Office | Protects links in Office applications. |
| Track Clicks | Records when users click a protected link. |
| Scan URLs | Scans links in real time when they are clicked. |
| Enable For Internal Senders | Applies the policy to mail sent inside the organization as well as mail from outside. |
| Allow Click Through | Lets users continue past the warning page to a link flagged as malicious. Leaving this off is the stricter setting. |
| Disable URL Rewrite | Turns off link rewriting, leaving the click time check in place without changing how the link looks. |
| Enable Organization Branding | Puts the organization's branding on warning pages. |
| Deliver Message After Scan | Holds a message until its links have been scanned. |
| Custom Notification Text | The wording shown to users about the scan. Greyed out until **Deliver Message After Scan** is on. |
| Do Not Rewrite URLs | URLs, domains or wildcard patterns the policy leaves untouched, for example `*.example.com` or `https://example.com`. Entries are validated as you add them and an entry that is not a valid URL, domain or pattern is rejected. |

## Safe Links Rule Configuration

**Rule Information**

| Field | Description |
| ----- | ----------- |
| Rule Name (Auto-generated) | Read only. Filled in for you as the policy name followed by `_Rule`. |
| Priority | The order the rule will be evaluated in against other Safe Links rules. Lower numbers are evaluated first, and the value must be 0 or greater. |
| Enable Rule | Whether the configuration is active once deployed. On by default. |
| Comments | Free text kept against the rule. |

**Applies To:**

| Field | Description |
| ----- | ----------- |
| Domains | Recipient domains the policy applies to. |
| Groups | Groups whose members the policy applies to. |
| Recipients | Individual recipients the policy applies to. |

**Exceptions:**

| Field | Description |
| ----- | ----------- |
| Domains | Recipient domains excluded from the policy. |
| Groups | Groups whose members are excluded from the policy. |
| Recipients | Individual recipients excluded from the policy. |

{% hint style="warning" %}
The domain, group and recipient pickers read from the tenant you currently have selected, so a template scoped with them carries that tenant's objects. Where a template is meant for several customers, scope it after deployment rather than here, or keep the scoping to values that exist in every tenant you will deploy to.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

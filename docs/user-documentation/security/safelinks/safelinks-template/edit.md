# Edit Safe Links Template

Opens a saved Safe Links policy template with its stored settings loaded in. The form is the same as [create.md](create.md "mention"), with one difference: **Policy Name** is fixed, since changing it would make the template deploy a different policy from the one it was built for.

Editing a template changes only what future deployments will create. Policies already deployed from it are untouched.

## Template Information

| Field | Description |
| ----- | ----------- |
| Template Name | Required. Names the template. |
| Template Description | Describe what this template is used for. |

## Safe Links Policy Configuration

**Policy Settings**

| Field | Description |
| ----- | ----------- |
| Policy Name | Read only. The name the policy will be created with in each tenant you deploy to. |
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
| Rule Name (Auto-generated) | Read only. Shows the rule name stored with the template. |
| Priority | The order the rule will be evaluated in against other Safe Links rules. Lower numbers are evaluated first, and the value must be 0 or greater. |
| Enable Rule | Whether the configuration is active once deployed. |
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

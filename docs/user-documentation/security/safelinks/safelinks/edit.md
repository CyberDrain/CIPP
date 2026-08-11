# Edit Safe Links Policy

Opens an existing Safe Links policy and its rule together, so a change to the protection settings and a change to who receives them are made in one place. The form is the same as [add.md](add.md "mention") with the current values loaded in, and one difference: **Policy Name** is fixed and cannot be changed once the policy exists.

## Safe Links Policy Configuration

**Policy Settings**

| Field | Description |
| ----- | ----------- |
| Policy Name | Read only. A policy cannot be renamed after it is created. |
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
| Rule Name (Auto-generated) | Read only. Shows the existing rule's name. |
| Priority | The order this rule is evaluated in against other Safe Links rules. Lower numbers are evaluated first, and the value must be 0 or greater. |
| Enable Rule | Whether the configuration is active. |
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

{% hint style="info" %}
Changes to Safe Links policies and rules may take up to 6 hours to propagate throughout your organization.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

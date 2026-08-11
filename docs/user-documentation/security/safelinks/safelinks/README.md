# Safe Links Policies

Safe Links rewrites and checks links in mail, Teams and Office documents at the moment someone clicks them. In Exchange Online this is really two objects: a policy holding the protection settings, and a rule deciding who the policy applies to. CIPP joins the pair back together so each row is one complete configuration, and flags the cases where the pair has come apart.

## Action Buttons

{% content-ref url="add.md" %}
[add.md](add.md)
{% endcontent-ref %}

## Filters

| Filter | Description |
| -------------- | -------------------------------------------------- |
| Enabled Rules  | Narrows the table to configurations that are on.    |
| Disabled Rules | Narrows the table to configurations that are off.   |

## Table Details

| Column | Description |
| ----------------------------- | ------------------------------------------------------------------------------------------------------- |
| Policy Name                   | The Safe Links policy's name. Empty on a row that is a rule with no policy behind it.                     |
| Configuration Status          | Whether the policy and rule pair is intact. Values are listed below.                                      |
| Is Valid                      | Whether Exchange Online considers the policy itself valid.                                                |
| State                         | Whether the configuration is enabled or disabled.                                                         |
| Priority                      | The order the rule is evaluated in against other Safe Links rules. Lower numbers are evaluated first.      |
| Description                   | The policy's description, or the rule's comments on a row with no policy.                                 |
| Recipient Domain Is           | The recipient domains the policy applies to.                                                              |
| Sent To                       | The individual recipients the policy applies to.                                                          |
| Sent To Member Of             | The groups whose members the policy applies to.                                                           |
| Except If Sent To             | Recipients excluded from the policy.                                                                      |
| Except If Sent To Member Of   | Groups whose members are excluded from the policy.                                                        |
| Except If Recipient Domain Is | Recipient domains excluded from the policy.                                                               |
| Do Not Rewrite Urls           | The URL patterns the policy leaves untouched.                                                             |
| Enable Safe Links For Email   | Whether links in email are protected.                                                                     |
| Enable Safe Links For Teams   | Whether links in Teams are protected.                                                                     |
| Enable Safe Links For Office  | Whether links in Office applications are protected.                                                       |
| Track Clicks                  | Whether user clicks on protected links are recorded.                                                      |
| Scan Urls                     | Whether links are scanned in real time when clicked.                                                      |
| Enable For Internal Senders   | Whether the policy also applies to mail sent inside the organization.                                      |
| Deliver Message After Scan    | Whether a message is held until its links have been scanned.                                              |
| Allow Click Through           | Whether users can continue past a warning page to a link flagged as malicious.                            |
| Disable Url Rewrite           | Whether link rewriting is turned off, leaving the click time check in place without changing the link text. |
| Enable Organization Branding  | Whether warning pages carry the organization's branding.                                                  |
| When Created                  | When the policy was created.                                                                              |
| When Changed                  | When the policy was last modified.                                                                        |

### Configuration Status

| Value | Meaning |
| ----- | ------- |
| `Complete` | Both a policy and its matching rule exist. This is the healthy state. |
| `Policy Only (Missing Rule)` | The protection settings exist but nothing scopes them to anyone, so the policy is not applying. |
| `Rule Only (Missing Policy)` | A rule points at a policy that does not exist. The named policy is shown in the value. |
| `Built-In Rule Only (No Associated Policy)` | A Microsoft managed Safe Links rule with no separate policy behind it. |

{% hint style="warning" %}
Anything other than `Complete` means the configuration is not doing what its name suggests. A **Policy Only** row is protection nobody is receiving, and a **Rule Only** row is a scope pointing at nothing. Both are worth resolving rather than leaving in place.
{% endhint %}

{% hint style="info" %}
Changes to Safe Links policies and rules may take up to 6 hours to propagate throughout your organization.
{% endhint %}

## Table Actions

Microsoft's preset security policies and the built-in protection policy are managed by Microsoft and cannot be changed here, so every action below is greyed out on those rows.

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Safe Links Policy</td><td>Opens the <a data-mention href="edit.md">edit.md</a> page for the selected policy.</td><td>false</td></tr><tr><td>Enable Rule</td><td>Switches the configuration on. Greyed out when it is already enabled.</td><td>true</td></tr><tr><td>Disable Rule</td><td>Switches the configuration off, leaving it in place but not applying. Greyed out when it is already disabled.</td><td>true</td></tr><tr><td>Set Priority</td><td>Changes the order the rule is evaluated in, prompting for the new priority number. Lower numbers are evaluated first, and the value must be at least 0.</td><td>false</td></tr><tr><td>Create template based on policy</td><td>Saves the selected policy and its rule as a Safe Links policy template, so it can be redeployed to other tenants.</td><td>false</td></tr><tr><td>Delete Rule</td><td>Permanently removes both the policy and the rule.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}

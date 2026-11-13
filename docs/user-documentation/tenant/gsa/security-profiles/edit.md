# Edit Security Profile

Creates or edits a security profile in the selected tenant. Open it with **Add Profile** or **Edit Profile** on the Security Profiles page. A new profile needs a priority no other profile uses. Changes are written to the tenant when you save.

## Fields

| Field       | Description                                                                                                                        |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Name        | Required.                                                                                                                          |
| Priority    | Required, from 100 to 64999. Lower numbers are processed first. The built-in baseline profile always stays at 65000, so it is greyed out for that profile. |
| Enabled     | Whether the security profile is enabled.                                                                                           |
| Description | Optional.                                                                                                                          |

## Filtering policies

Pick from the filtering policies in this tenant. Each one can only be linked once, and link priorities must be unique within the profile.

| Field            | Description                                                                        |
| ---------------- | ---------------------------------------------------------------------------------- |
| Filtering policy | A filtering policy in this tenant.                                                 |
| Priority         | From 100 to 65000. Lower numbers are processed first.                              |
| Enabled          | Whether this policy is active in the profile.                                      |
| Logging          | Whether traffic matched by this policy is logged.                                  |

Results are listed for each change. Turning logging on or off for a policy unlinks and relinks it, because Microsoft does not allow changing it in place.

Editing the baseline profile's filtering policies applies them to all Internet Access traffic, without a Conditional Access policy.

If this profile was deployed from a template, the next deploy of that template puts the template's settings back.

{% include "../../../../../.gitbook/includes/feature-request.md" %}

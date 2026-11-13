# Add or Edit Security Profile Template

Creates a new security profile template, or edits an existing one.

## Fields

| Field       | Description                                                                                                                  |
| ----------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Name        | Required. Used as the security profile name in every tenant, so it must be unique in CIPP.                                   |
| Priority    | Required, from 100 to 64999. Lower numbers are processed first. 65000 belongs to the tenant's built-in baseline profile, and no two templates can share a priority. |
| Enabled     | Whether the security profile is enabled.                                                                                     |
| Description | Optional. Saved with the template and written to the profile in each tenant.                                                 |

## Filtering policies

A template needs at least one filtering policy. Use **Add filtering policy** for more, and the bin icon to remove one.

| Field                     | Description                                                                                     |
| ------------------------- | ----------------------------------------------------------------------------------------------- |
| Filtering policy template | The filtering policy template to link. Each one can only be linked once.                        |
| Priority                  | From 100 to 65000, unique within the template. Lower numbers are processed first.              |
| Enabled                   | Whether this policy is active in the profile.                                                   |
| Logging                   | Whether traffic matched by this policy is logged.                                               |

{% include "../../../../../.gitbook/includes/feature-request.md" %}

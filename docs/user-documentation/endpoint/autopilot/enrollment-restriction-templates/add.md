# Add Enrollment Restriction Template

Creates an enrollment restriction template. Templates can also be saved from an existing restriction with **Save as Template** on [README.md](../enrollment-restrictions/README.md "mention").

## Enrollment Restriction Template

| Field                                                            | Description                                                                                                                                                                       |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Platform                                                         | Android, iOS/iPadOS, macOS, or Windows.                                                                                                                                           |
| Name                                                             | The name of the restriction the template creates. Deploying to a tenant that already has a restriction with this name on the same platform updates that restriction.             |
| Priority                                                         | The position a new restriction is placed at, where 1 is the highest. Leave blank to place it below each tenant's existing restrictions. Existing restrictions keep their position. |
| Description                                                      | Optional text describing the restriction.                                                                                                                                         |
| Who should this restriction apply to?                            | **Do Not Assign**, **Assign to All Users**, or **Assign to Custom Group**.                                                                                                        |
| Custom Group Names separated by comma. Wildcards (\*) are allowed | Shown for **Assign to Custom Group**. The names are looked up in each tenant the template is deployed to.                                                                         |

**Platform settings**

The platform settings are the same as when adding a restriction. Windows and iOS/iPadOS are described on [README.md](../enrollment-restrictions/README.md "mention"), macOS on [apple.md](../enrollment-restrictions/apple.md "mention"), and Android on [android.md](../enrollment-restrictions/android.md "mention").

{% include "../../../../../.gitbook/includes/feature-request.md" %}

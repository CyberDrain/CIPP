# Add Team

Creates a new team in the selected tenant, using Microsoft's standard team template. The Microsoft 365 group behind the team is created automatically, and its mail nickname is taken from the display name unless you set one.

## Details

| Field                                                      | Description                                                                                                                                                          |
| ---------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name                                               | The name of the team. Required.                                                                                                                                      |
| Description                                                | A description of what the team is for.                                                                                                                               |
| Mail Nickname (optional, used for the group email address) | The alias the team's group email address is built from. Letters, numbers, dots, dashes and underscores only. Leave empty to have it generated from the display name. |
| Select owner (must have a Teams license)                   | The user who will be added to the team as its owner. Required, and at least one owner has to be set for the team to be created.                                      |
| Team Visibility                                            | **Private Team** means people can only join if an owner adds them. **Public Team** means anyone in the organisation can join it.                                     |

{% include "../../../../../.gitbook/includes/feature-request.md" %}

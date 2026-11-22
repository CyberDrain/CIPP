# OneDrive Shortcuts

Lists the SharePoint library shortcuts in this user's OneDrive, whether they sit in the OneDrive root or the Shortcuts folder used by Microsoft's own OneDrive and SharePoint interfaces.

## Action Buttons

<details>

<summary>Add Shortcut</summary>

Opens a dialog that adds a shortcut to a SharePoint document library into the user's OneDrive. The button only appears if your CIPP role can edit users.

| Field             | Description                                                                                                                              |
| ----------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Site              | The SharePoint site to link to. Existing sites can be picked, or a site or subsite URL typed directly.                                   |
| Document library (optional) | One of the site's document libraries. Leave blank to use the site's default Documents library.                                 |
| Folder (optional) | A folder inside the chosen library, such as `Finance/2026`, to link to instead of the whole library. Appears once a library is picked. |
| Shortcut location | Where the shortcut is created: **OneDrive root** or **Shortcuts folder (Microsoft UI)**. Defaults to **Shortcuts folder (Microsoft UI)**. |
| Shortcut name (optional) | The name the shortcut is given. Leave blank to keep the library or site name. A name cannot contain any of the characters `"`, `*`, `:`, `<`, `>`, `?`, `/`, `\` or a vertical bar, cannot start or end with a space, cannot end with a period, and cannot be longer than 255 characters. |

</details>

## Table Details

| Column                  | Description                                                             |
| ----------------------- | ----------------------------------------------------------------------- |
| Name                    | The shortcut's file name.                                               |
| Location                | Whether the shortcut sits in the OneDrive root or the Shortcuts folder. |
| Site URL                | The SharePoint site the shortcut points to.                             |
| Created Date Time       | When the shortcut was created.                                          |
| Last Modified Date Time | When the shortcut was last changed.                                     |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Migrate to Shortcuts folder</td><td>Moves the shortcut from the OneDrive root into the Shortcuts folder. Greyed out unless the shortcut is still in the OneDrive root.</td><td>true</td></tr><tr><td>Remove Shortcut</td><td>Removes the shortcut from the user's OneDrive. The linked SharePoint content itself is unaffected.</td><td>true</td></tr></tbody></table>

{% include "../../../../../../.gitbook/includes/feature-request.md" %}

# New Endpoint Manager Template

Builds a new Intune Settings Catalog template from scratch, by searching the Intune Settings Catalog for the settings you want and giving each one a value. Use it when there is no existing policy to capture or import. The template is stored in CIPP and appears on [README.md](README.md "mention"), ready to deploy to tenants.

{% hint style="info" %}
A template that would not deploy is not saved, and the result lists what is wrong. Use **Validate template** while you build to find problems before you submit.
{% endhint %}

## Template details

| Field         | Description                                                                                                                                                                                          |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Template Name | The name of the template. Required. This is also the name the deployed policy takes, and the name CIPP matches on when deciding whether to overwrite an existing policy.                              |
| Description   | The description recorded against the template.                                                                                                                                                       |
| Platform      | The platform the policy is for: **Windows 10 and later**, **macOS**, **iOS/iPadOS**, **Android Enterprise**, **Android (AOSP)** or **Linux**. It decides which settings can be searched for. Defaults to **Windows 10 and later**. |
| Technology    | How the policy is managed: **MDM**, **MDM + Security settings management**, **Configuration Manager**, **Apple Remote Management** or **Linux MDM**. Narrows the settings you can find. Defaults to **MDM**. |

Platform and Technology are locked once the template has a setting in it. Remove the settings first if you need to change either.

### Validate template

Checks the template for anything that would stop it deploying, and lists every problem it finds. Nothing is saved. The button is greyed out until the template has at least one setting.

## Configured settings

Lists the settings in the template, with a count of how many there are. The card opens by itself while the template is empty, and can be expanded and collapsed once it has settings.

### Add setting

Opens an **Add a setting** dialog that searches the Settings Catalog for the platform you chose.

* Type at least two characters to search. Matches are found in the setting's name, category and description.
* The best matches are listed first, up to 100 at a time. Narrow the search to see more.
* Settings already in the template are left out of the results.
* Selecting a result adds it, along with any settings it depends on, and closes the dialog.

If a setting cannot be built from the Settings Catalog, for example because it needs a value in a specific format, the dialog says so and the setting is not added. Capture it from a tenant policy instead, using **Browse Catalog** on [README.md](README.md "mention").

### Setting rows

| Control      | Description                                                                                                  |
| ------------ | ------------------------------------------------------------------------------------------------------------ |
| Remove       | Removes the setting from the template.                                                                       |
| Add row      | Appends another row to a setting that holds a list of grouped entries. Greyed out when the setting is at its maximum number of rows. |
| Remove row N | Removes that row from a grouped setting. Greyed out when the setting is at its minimum number of rows.       |

## Setting values

Appears once the template has settings, with one field for each value. Each setting is rendered according to what it accepts: a true or false switch, a list of the options the setting allows, a list of values, or a free text or numeric field. It works the same way as the settings on [edit.md](edit.md "mention"), including CIPP custom variables in the dropdowns.

If the Intune Settings Catalog cannot be loaded, settings are shown by their definition identifiers instead. Values you change are still saved correctly.

## After saving

Once the template is saved, CIPP opens it in [edit.md](edit.md "mention") so you can carry on refining it.

{% include "../../../../../.gitbook/includes/feature-request.md" %}

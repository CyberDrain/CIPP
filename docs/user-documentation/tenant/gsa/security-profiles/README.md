# Security Profiles

This page lists the Global Secure Access security profiles in the selected tenant, read live from the tenant. A security profile groups filtering policies and is applied to users by a Conditional Access policy. The built-in **Baseline profile** (priority 65000) applies to all Internet Access traffic without one.

The **Templates** tab holds the security profile templates you deploy to tenants.

{% content-ref url="templates.md" %}
[templates.md](templates.md)
{% endcontent-ref %}

## Table Details

| Column                            | Description                                                              |
| --------------------------------- | ------------------------------------------------------------------------ |
| Name                              | The profile name.                                                        |
| Priority                          | The order the profile is processed in. Lower numbers go first.           |
| State                             | Whether the profile is enabled or disabled.                              |
| Filtering Policies                | The policies the profile links, as priority and name.                    |
| Conditional Access Policy Names   | The Conditional Access policies that apply the profile.                  |
| Description                       | The profile description.                                                 |

## Page Actions

<table><thead><tr><th>Action</th><th>Description</th></tr></thead><tbody><tr><td>Add Profile</td><td>Opens the <a href="edit.md">editor</a> to create a new security profile in the selected tenant.</td></tr><tr><td>Deploy Template</td><td>Opens the deploy drawer with the selected tenant already chosen. Pick a security profile template and select <strong>Deploy</strong>; you can add more tenants first.</td></tr></tbody></table>

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Profile</td><td>Opens the profile in the <a href="edit.md">editor</a>.</td><td>false</td></tr><tr><td>Save as Template</td><td>Saves the profile as a security profile template. Each linked filtering policy uses the filtering policy template with the same name, or gets a new one. If an existing template differs from the tenant policy, nothing is saved and the differences are listed. Greyed out for the built-in baseline profile.</td><td>false</td></tr><tr><td>Delete Profile</td><td>Deletes the profile from the tenant. Its filtering policies stay. It is refused while a Conditional Access policy applies the profile, and is greyed out for the built-in baseline profile.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full profile.</td><td>false</td></tr></tbody></table>

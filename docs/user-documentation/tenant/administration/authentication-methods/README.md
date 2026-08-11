# Authentication Methods

Each row on this page is one authentication method configuration in the tenant, such as Microsoft Authenticator, FIDO2 or Temporary Access Pass, showing whether the method is enabled and who it applies to. The Registration Campaign tab alongside it controls prompting users to move to the Authenticator app.

## Table Details

| Column          | Description                                                                                                                                                                                |
| --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Id              | The method's identifier in Microsoft Graph, such as `MicrosoftAuthenticator`, `Fido2` or `TemporaryAccessPass`.                                                                            |
| State           | Whether the method is enabled or disabled for the tenant.                                                                                                                                  |
| Include Targets | Who the method applies to. The cell is a button showing how many targets are set; selecting it opens them in a dialog. A method scoped to everyone shows a single target of `all_users`. |
| Exclude Targets | Any groups excluded from the method, shown the same way.                                                                                                                                   |

Each row is one of the derived types of the Graph resource `authenticationMethodConfiguration`, so the properties available beyond those four differ by method. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/authenticationmethodconfiguration?view=graph-rest-1.0#properties).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Enable Policy</td><td>Enables the selected authentication method for the tenant.</td><td>true</td></tr><tr><td>Disable Policy</td><td>Disables the selected authentication method for the tenant.</td><td>true</td></tr><tr><td>Deploy to Custom Group</td><td>Scopes the method to one or more groups chosen from the tenant's group list. The groups selected replace whatever the method was previously scoped to.</td><td>true</td></tr><tr><td>Assign to All Users</td><td>Scopes the method to every user in the tenant, replacing any existing targeting.</td><td>false</td></tr><tr><td>Configure</td><td>Opens a form of settings specific to the selected method. Only available where the method is enabled and has settings to configure, which means Temporary Access Pass, Microsoft Authenticator, Email, QR Code PIN, FIDO2, Voice or SMS.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
Both targeting actions replace the method's include targets rather than adding to them. Deploying to a custom group on a method currently scoped to all users removes the all-users scope, so anyone outside the chosen groups loses the method.
{% endhint %}

## Method Settings

**Configure** shows only the settings that apply to the selected method, pre-filled with the method's current values.

| Method                  | Setting                                                         | Description                                                                                                                |
| ----------------------- | --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Temporary Access Pass   | One-time use only                                               | Whether a pass is consumed by its first use, rather than remaining valid until it expires.                                 |
| Temporary Access Pass   | Minimum lifetime (minutes)                                      | The shortest lifetime an administrator may set when issuing a pass.                                                        |
| Temporary Access Pass   | Maximum lifetime (minutes)                                      | The longest lifetime an administrator may set when issuing a pass.                                                         |
| Temporary Access Pass   | Default lifetime (minutes)                                      | The lifetime applied when none is specified.                                                                               |
| Temporary Access Pass   | Default length (characters)                                     | How many characters a generated pass contains.                                                                             |
| Microsoft Authenticator | Allow software OATH tokens                                      | Whether the Authenticator app may be used as a software OATH token generator.                                              |
| Microsoft Authenticator | Show application name in push and passwordless notifications    | Whether approval prompts name the application being signed in to. Default, Enabled or Disabled.                            |
| Microsoft Authenticator | Show geographic location in push and passwordless notifications | Whether approval prompts show where the sign-in came from. Default, Enabled or Disabled.                                   |
| Microsoft Authenticator | Companion app allowed state                                     | Whether approvals may be completed from a companion app. Default, Enabled or Disabled.                                     |
| Email                   | Allow external users to use Email OTP                           | Whether guests from outside the tenant may authenticate with an emailed one-time code. Default, Enabled or Disabled.       |
| Email                   | Exclude group(s)                                                | Groups excluded from Email OTP.                                                                                            |
| QR Code PIN             | Standard QR code lifetime (days, 1-395)                         | How long an issued QR code remains valid.                                                                                  |
| QR Code PIN             | PIN length (8-20)                                               | How many digits the accompanying PIN contains.                                                                             |
| FIDO2                   | Enforce attestation                                             | Whether security keys must prove their make and model before they can be registered.                                       |
| FIDO2                   | Allow self-service registration                                 | Whether users may register their own security keys.                                                                        |
| Voice                   | Allow office phone registration                                 | Whether users may register an office number as well as a mobile for voice call verification.                               |
| SMS                     | Use for sign-in                                                 | Whether SMS may be used to sign in, rather than only as a second factor. Applies to every group the method is targeted at. |

{% hint style="info" %}
Enabling FIDO2 with **Enable Policy** rather than **Configure** turns on attestation enforcement and self-service registration, as those are the defaults CIPP applies. Use **Configure** afterwards if either should be off.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

# Applications

Applications lists the applications available for deployment through Intune for the selected tenant, along with how each one is currently assigned and excluded. From here you can deploy new applications, change assignments, save an application as a reusable template, or remove an application from the tenant. The list covers line-of-business and managed applications, plus any other application that already has an assignment, so it will not show every item in the Intune catalog.

## Action Buttons

<details>

<summary>Add Application</summary>

Opens the Application Deployment drawer. Pick an application type, select one or more tenants, complete the type-specific fields, then choose how the application should be assigned and select **Deploy Application**. Deployments are queued rather than applied immediately, so progress is tracked on the Application Queue page.

**MSP Vendor App**

Deploys an RMM or security agent installer as a Win32 application. Choose the tool under **Select MSP Tool** and the form then asks only for that vendor's details. Two fields are common to all of them:

| Field                           | Description                                           |
| ------------------------------- | ----------------------------------------------------- |
| Select MSP Tool                 | The vendor agent to deploy.                           |
| Intune Application Display Name | The name the application will appear under in Intune. |

Site-level fields repeat once for every tenant you selected, labelled with that tenant's name, so one deployment can carry a different identifier for each customer.

**Datto RMM**

| Field      | Description                                                                                                   |
| ---------- | ------------------------------------------------------------------------------------------------------------- |
| Server URL | The platform URL for your Datto instance, including `https://`, for example `https://pinotage.rmm.datto.com`. |
| Datto ID   | Per tenant. The Datto site identifier for that customer.                                                      |

**Syncro RMM**

| Field      | Description                                                                           |
| ---------- | ------------------------------------------------------------------------------------- |
| Client URL | Per tenant. The full download URL of the agent installer for that customer's account. |

**Huntress**

| Field            | Description                                                                 |
| ---------------- | --------------------------------------------------------------------------- |
| Account Key      | Your Huntress MSP account key, shared across all tenants in the deployment. |
| Organization Key | Per tenant. The organization identifier for that customer.                  |

Huntress guidance on choosing organization keys is in their article on [account keys, organization keys and agent tags](https://support.huntress.io/hc/en-us/articles/4404012734227-Using-Account-Keys-Organization-Keys-and-Agent-Tags).

**CW Automate**

| Field                             | Description                                                          |
| --------------------------------- | -------------------------------------------------------------------- |
| Automate Server (including HTTPS) | The FQDN of your Automate server, including `https://`.              |
| Installer Token                   | Per tenant. A generated agent installer token.                       |
| Location ID                       | Per tenant. The Automate location the agent should register against. |

Installer tokens are generated on the Automate server. This [community script](https://forums.mspgeek.org/files/file/50-generate-agent-installertoken/) covers one way of producing them.

**CW Command**

ConnectWise RMM, previously known as Command and before that Continuum.

| Field      | Description                                                                        |
| ---------- | ---------------------------------------------------------------------------------- |
| Client URL | Per tenant. The full download URL of the agent installer for that customer's site. |

{% hint style="info" %}
Datto RMM, CW Automate and CW Command are community contributions and are not covered by a vendor sponsorship. CIPP shows a notice to this effect when one of them is selected, and support for these is through the Discord community rather than the vendor.
{% endhint %}

{% hint style="warning" %}
ImmyBot was removed from the list of deployable applications. See the [ImmyBot documentation](https://www.immy.bot/documentation/) for supported deployment methods.
{% endhint %}

**Store App**

Deploys an application from the Microsoft Store using its WinGet package identifier. Enter a term under **Search Packages** and select **Search** to populate the **Select Package** list, which fills in the identifier, name and description for you. You can also skip the search and type the package details in directly.

| Field                     | Description                                                                                                    |
| ------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Search Packages           | A term to search the Store catalog with.                                                                     |
| Select Package            | The matching package to use, which populates the three fields below.                                           |
| WinGet Package Identifier | The package identifier to install, for example `Mozilla.Firefox`.                                              |
| Application Name          | The name the application will appear under in Intune.                                                          |
| Description               | Optional text shown in Intune and the Company Portal.                                                          |
| Install as system         | Installs under the SYSTEM account rather than as the signed-in user. Enabled by default.                       |
| Mark for Uninstallation   | Deploys the application with an uninstall intent, so it is removed from targeted devices instead of installed. |

**Chocolatey App**

Deploys an application through the [Chocolatey](https://chocolatey.org/) package manager. Enter a term under **Search Packages** and select **Search** to populate the **Select Package** list, or enter the package name directly. Packages can be pulled from your own trusted repository rather than the public one.

| Field                       | Description                                                                                                                                                                            |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Search Packages             | A term to search the Chocolatey repository with.                                                                                                                                       |
| Select Package              | The matching package to use, which populates the fields below.                                                                                                                         |
| Chocolatey Package Name     | The package to install, for example `googlechrome`.                                                                                                                                    |
| Application Name            | The name the application will appear under in Intune.                                                                                                                                  |
| Description                 | Optional text shown in Intune and the Company Portal.                                                                                                                                  |
| Custom Repository URL       | An alternative Chocolatey feed to install from, for use with a private or internal repository.                                                                                         |
| Custom Chocolatey Arguments | Additional arguments passed to the install command, entered with their full syntax and flags. Variables are supported, for example `--install-arguments '/S /KEY=%customlicensekey%'`. |
| Install as system           | Installs under the SYSTEM account rather than as the signed-in user. Enabled by default.                                                                                               |
| Disable Restart             | Suppresses any device restart after installation. Enabled by default.                                                                                                                  |
| Mark for Uninstallation     | Deploys the application with an uninstall intent, so it is removed from targeted devices instead of installed.                                                                         |

{% hint style="info" %}
Chocolatey deployments use a [prepared IntuneWin file](https://github.com/CyberDrain/CIPP/blob/dev/backend/AddChocoApp/IntunePackage.intunewin?raw=true) containing `install.ps1` and `uninstall.ps1`, which install Chocolatey and then run the install or uninstall command. You are strongly encouraged to download and inspect this package before using it, and you can substitute your own in a fork if you would rather not rely on it.
{% endhint %}

**Microsoft Office**

Deploys Microsoft 365 Apps using Intune's built-in Office suite deployment.

| Field                           | Description                                                                                                                                                                                                                 |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Excluded Apps                   | The applications to leave out of the installation. Access, Excel, OneNote, Outlook, PowerPoint, Publisher, Teams, Word, Skype For Business and Bing can each be excluded.                                                   |
| Update Channel                  | The servicing channel the installation is tied to: Current Channel, Current (Preview), Monthly Enterprise, Semi-Annual Enterprise or Semi-Annual Enterprise (Preview).                                                      |
| Languages                       | The language packs to install alongside the applications. At least one is required.                                                                                                                                         |
| Use Shared Computer Activation  | Licenses the installation per session rather than per device, for multi-user machines such as session hosts.                                                                                                                |
| 64 Bit (Recommended)            | Installs the 64-bit build. Enabled by default.                                                                                                                                                                              |
| Remove other versions           | Uninstalls existing Office installations as part of the deployment. Enabled by default.                                                                                                                                     |
| Accept License                  | Accepts the license terms on the user's behalf so the installation runs without prompting. Enabled by default.                                                                                                              |
| Use Custom XML Configuration    | Replaces the options above with a configuration XML of your own.                                                                                                                                                            |
| Custom Office Configuration XML | The configuration to apply when the switch above is enabled. Every other Office option on this form is ignored when custom XML is supplied. Use the [Office Customization Tool](https://config.office.com/) to generate it. |

**Custom Application**

Packages a pair of PowerShell scripts as a Win32 application, for anything that is not covered by the other types.

| Field                                               | Description                                                                                                                                                                                                                                 |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Application Name                                    | The name the application will appear under in Intune.                                                                                                                                                                                       |
| Publisher                                           | The publisher shown in Intune and the Company Portal. Defaults to CIPP when left blank.                                                                                                                                                     |
| Description                                         | Optional text shown in Intune and the Company Portal.                                                                                                                                                                                       |
| Install Script (PowerShell)                         | The script contents that install the application, uploaded to Intune as `install.ps1`.                                                                                                                                                      |
| Uninstall Script (PowerShell, Optional)             | The script contents that remove the application, uploaded as `uninstall.ps1`. Leaving this blank means the application has no uninstall action.                                                                                             |
| Use Detection Script instead of file/path detection | Swaps the two path detection fields for a detection script.                                                                                                                                                                                 |
| Detection Path                                      | The file or folder that indicates the application is installed, for example `C:\Program Files\MyApp`. When left blank, CIPP creates a detection rule looking for a marker file under `%ProgramData%\CIPPApps\` named after the application. |
| Detection File/Folder Name                          | A specific file to look for inside the detection path, for example `app.exe`. When left blank, the last segment of the detection path is treated as the item to detect.                                                                     |
| Detection Script                                    | The script that verifies the application is installed, used when script detection is enabled. Exiting with code 0 and writing to STDOUT counts as detected.                                                                                 |
| Install as System                                   | Runs the scripts under the SYSTEM account rather than as the signed-in user. Enabled by default.                                                                                                                                            |
| Disable Restart                                     | Suppresses any device restart after installation. Enabled by default.                                                                                                                                                                       |
| Run as 32-bit on 64-bit system                      | Forces the scripts to run in 32-bit PowerShell. Leave off unless the application requires it.                                                                                                                                               |
| Enforce signature check                             | Requires the scripts to be digitally signed before Intune will run them.                                                                                                                                                                    |
| Mark for Uninstallation                             | Deploys the application with an uninstall intent, so it is removed from targeted devices instead of installed.                                                                                                                              |

**Assignment Options**

Every application type except the MSP apps offers the same assignment choices at the bottom of the form.

| Option                          | Description                                                                                                                    |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Do not assign                   | Creates the application in Intune without targeting anyone.                                                                    |
| Assign to all users             | Targets all licensed users in each selected tenant.                                                                            |
| Assign to all devices           | Targets all devices in each selected tenant.                                                                                   |
| Assign to all users and devices | Targets both of the above.                                                                                                     |
| Assign to Custom Group          | Targets named groups. Enter the group display names separated by commas, where `*` may be used as a wildcard.                  |
| Exclude Group Names             | Shown for every option except Do not assign. Excludes the named groups, again comma separated and accepting `*` as a wildcard. |

{% hint style="info" %}
Group names here are matched by display name across every selected tenant, so a wildcard such as `SEC-Workstations*` lets one deployment target similarly named groups in each customer without listing them individually.
{% endhint %}

</details>

<details>

<summary>Sync VPP</summary>

Triggers a sync of all Apple Volume Purchase Program (VPP) tokens for the selected tenant, so that recently purchased licenses and applications are pulled into Intune.

</details>

## Table Details

The properties returned are for the Graph resource type `mobileApp`. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/intune-apps-mobileapp?view=graph-rest-1.0#properties).

CIPP adds the following columns by resolving each application's assignments against the groups in the tenant:

| Column         | Description                                                                                                                                                                                                       |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| App Assignment | The targets the application is assigned to, each followed by its assignment intent in brackets. Group assignments show the group's display name, and broad assignments show as All Devices or All Licensed Users. |
| App Exclude    | The groups that are excluded from the application's assignments, each followed by the assignment intent in brackets.                                                                                              |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Assign to All Users</td><td>Assigns the application to all licensed users in the tenant using the chosen assignment intent, with optional exclusion groups and an optional assignment filter.</td><td>true</td></tr><tr><td>Assign to All Devices</td><td>Assigns the application to all devices in the tenant using the chosen assignment intent, with optional exclusion groups and an optional assignment filter.</td><td>true</td></tr><tr><td>Assign Globally (All Users / All Devices)</td><td>Assigns the application to both all licensed users and all devices in the tenant using the chosen assignment intent, with optional exclusion groups and an optional assignment filter.</td><td>true</td></tr><tr><td>Assign to Custom Group</td><td>Assigns the application to specific groups, or excludes specific groups from it, using the chosen assignment intent and an optional assignment filter. Selecting Exclude together with Replace and no groups clears all existing exclusions while leaving the included assignments in place.</td><td>true</td></tr><tr><td>Save as Template</td><td>Saves the selected application(s) as a named application template that can be redeployed to other tenants from Application Templates.</td><td>true</td></tr><tr><td>Delete Application</td><td>Removes the application from Intune for the tenant. This also removes its assignments, and the application will be uninstalled or stop being offered depending on how it was assigned.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
Every assignment action offers an assignment mode. **Append** keeps the existing assignments and adds or overwrites only the targets you selected. **Replace** overwrites existing assignments, and for Assign to Custom Group it replaces only the direction you chose (include or exclude), leaving the other direction and any All Users or All Devices targets intact.
{% endhint %}

{% hint style="warning" %}
Choosing the Uninstall intent creates an uninstall assignment, which will remove the application from the targeted devices rather than simply unassigning it.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

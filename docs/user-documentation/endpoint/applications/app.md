# View Application

Opens from **View Application** on the [Applications](list.md) list and shows one Intune application, how it is assigned, and how it has deployed.

The header shows the application type, its ID, when it was last changed, and a link to the application in the Microsoft Intune admin center. The **Actions** menu has the same actions as the Applications list: assign the application, save it as a template, or delete it.

## Application

The application's publisher, version, publishing state, whether it is featured in the Company Portal and when it was created. For a Win32 application this also shows the install and uninstall commands, whether it installs as the user or the system, its restart behaviour and its first detection rule.

## Assignments

One row per assignment: who it targets (all users, all devices or a group), whether it includes or excludes that target, the assignment intent and any device filter. The Filter column only appears when an assignment uses one.

| Action            | Description                                                                                                                                                                       |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Remove assignment | Removes that one assignment and keeps the application's other assignments as they are. Not offered on an assignment that comes from a policy set; change it on the policy set. |

## Deployment Status

The same Devices and Users install status as the **More Info** flyout on the Applications list.

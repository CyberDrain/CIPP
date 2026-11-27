# View Device

Opens from **View Device** on the [Devices](../devices.md) list and shows one Microsoft Entra device, its extension attributes and its groups. The switcher next to the device name moves to another device without going back to the list.

The header shows how the device is joined, its object ID, when it last signed in, and a link to the device in the Microsoft Entra admin center. When Intune has a record for the device, **View in CIPP Intune** opens CIPP's Intune device page for it. The **Actions** menu has the same device actions as the Devices list.

## Device

Whether the device is enabled, its join type, operating system and version, manufacturer and model, profile type, enrollment type, whether it is managed by an MDM and compliant, whether it syncs from on-premises Active Directory, when it was registered and its device ID.

## Extension attributes

The device's extension attributes 1 to 15 that have a value. Change one with **Set Extension Attribute** in the Actions menu. These attributes are often used in dynamic device group rules.

## Groups

The groups the device is a member of, with each group's type and whether membership is assigned or dynamic.

| Action            | Description                                                                                                              |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------ |
| View Group        | Opens the group's page.                                                                                                  |
| Remove from group | Removes the device from the group. Greyed out for a dynamic group, where membership comes from the group's rule instead. |

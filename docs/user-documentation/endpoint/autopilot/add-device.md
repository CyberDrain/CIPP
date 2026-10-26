# Add Autopilot Device

Registers devices in a customer tenant so they deploy as corporate devices. The wizard offers two deployment types: registering devices to Windows Autopilot, or uploading corporate identifiers for Windows Autopilot device preparation.

Windows Autopilot registration goes through the Partner Center device batch API. Devices can be identified in any of three ways:

* Hardware hash, obtained from the OEM or from an on-device script
* Serial number together with both manufacturer and model
* Windows product key ID

{% hint style="warning" %}
Windows Autopilot registration goes through the Partner Center API rather than Graph, so a reseller relationship with the customer tenant is required. GDAP on its own is not enough, and without a reseller relationship the import will fail. Where one does not yet exist, the [sam-setup-wizard.md](../../cipp/sam-setup-wizard.md "mention") can generate the invitation link to send to the customer using the option **Add Tenant** and then **Get Reseller Invite Link**.
{% endhint %}

## Importing Devices

{% stepper %}
{% step %}
### Deployment Type

Choose how the devices should be registered.

| Option                                     | Description                                                                                                                                                                                 |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Windows Autopilot                          | Registers devices to Windows Autopilot by serial number, Windows product key ID or hardware hash.                                                                                           |
| Device Preparation (Corporate Identifiers) | Uploads each device's manufacturer, model and serial number as a corporate identifier, so the device is recognised as corporate-owned and can enrol through Windows Autopilot device preparation. |

Switching between the two clears anything already entered for the other type.
{% endstep %}

{% step %}
### Tenant Selection

Select the tenant the devices should be registered to. Only one tenant can be chosen.
{% endstep %}

{% step %}
### Device Import

Build the list of devices to register. Three buttons sit above the list: **Download Template**, **Import from CSV** and **Manual Import**. What they accept depends on the deployment type.

**Windows Autopilot**

**Download Template** produces a CSV containing the expected column headers, ready to fill in.

**Import from CSV** reads a file into the list. Only `SerialNumber` is required. Headers may use any of the accepted names below, and a headerless file is also accepted, in which case the columns are read in the order serial number, product key, hardware hash, group tag, with at least three columns present.

| Template column     | Also accepted as                   |
| ------------------- | ---------------------------------- |
| SerialNumber        | Serialnumber, Device Serial Number |
| oemManufacturerName | Manufacturer, Manufacturer name    |
| modelName           | Model, Device model                |
| productKey          | Product ID, Windows Product ID     |
| hardwareHash        | Hardware hash, Hardware Hash       |
| groupTag            | Group Tag                          |

**Manual Import** opens a dialogue for typing devices in one row at a time. Pressing Enter in the Product ID field adds another row. Rows are validated as they are entered, and the Add button stays disabled until every problem is resolved.

Each row must satisfy the following:

* Serial numbers must be unique within the batch.
* Product IDs must be unique within the batch, and exactly 13 characters where supplied.
* A row with a serial number must also carry either both manufacturer and model, or a hardware hash.

Devices already in the list can be removed with the Delete Row action.

**Device Preparation (Corporate Identifiers)**

Every device needs a manufacturer, model and serial number. None of the three may contain a comma, and the same combination cannot appear twice. These rules apply to a CSV as well as to manual entry, and a file that breaks them is rejected with a list of the problems. A headerless file is read in the order manufacturer, model, serial number, which is the layout the Intune admin center uses for corporate identifiers.

| Template column | Also accepted as                                             |
| --------------- | ------------------------------------------------------------ |
| manufacturer    | Manufacturer, Manufacturer name, oemManufacturerName         |
| model           | Model, Device model, modelName                               |
| serialNumber    | Serial Number, Serial number, Device Serial Number, SerialNumber |

**Overwrite existing identifiers** replaces identifiers that are already in the tenant. With it off, a device whose identifier already exists can fail to import.
{% endstep %}

{% step %}
### Extra Options

Windows Autopilot only.

**Group Name** names the Partner Center device batch the devices are added to. Leaving it blank generates one automatically. Entering the name of a batch that already exists appends the devices to it rather than creating a new one. The match ignores case, and the existing batch's spelling is used.
{% endstep %}

{% step %}
### Confirmation

Review the tenant, the device list and, for Windows Autopilot, the batch name, then submit.

For Windows Autopilot, CIPP waits up to about 30 seconds for Partner Center to finish processing and then reports the outcome for each device individually, including the error code and description where one failed. For corporate identifiers, CIPP reports whether each identifier imported.
{% endstep %}
{% endstepper %}

## Known Issues / Limitations

* Guessing the manufacturer and model from the device's packaging is unreliable. The hardware hash or the Windows product key ID are far more dependable, and some manufacturers print the product key ID on the box.
* CIPP only waits about 30 seconds for the import job to report back. On a large batch, or when appending to an existing batch, it may give up before Partner Center finishes and shows a warning naming the batch and the job's current status. The registration usually completes regardless, so check the Autopilot Devices list about ten minutes later rather than resubmitting.
* The group tag column is forwarded with each device, but the Partner Center device API has no group tag field, so the tag may not appear on the registered device. Set it afterwards with **Edit Group Tag** on the Autopilot Devices page if it is missing.
* For Windows Autopilot, validation runs on manually entered rows only. A CSV is loaded without the duplicate, product key length or serial number companion checks being applied, so errors in a file surface as failures from Partner Center at the end rather than at import time.

{% include "../../../../.gitbook/includes/feature-request.md" %}

# Add Autopilot Device

Registers devices to Windows Autopilot in a customer tenant through the Partner Center device batch API. Devices can be identified in any of three ways:

* Hardware hash, obtained from the OEM or from an on-device script
* Serial number together with both manufacturer and model
* Windows product key ID

{% hint style="warning" %}
Registration goes through the Partner Center API rather than Graph, so a reseller relationship with the customer tenant is required. GDAP on its own is not enough, and without a reseller relationship the import will fail. Where one does not yet exist, the [sam-setup-wizard.md](../../cipp/sam-setup-wizard.md "mention") can generate the invitation link to send to the customer using the option **Add Tenant** and then **Get Reseller Invite Link**.
{% endhint %}

## Importing Devices

{% stepper %}
{% step %}
### Tenant Selection

Select the tenant the devices should be registered to. Only one tenant can be chosen.
{% endstep %}

{% step %}
### Device Import

Build the list of devices to register. Three buttons sit above the list:

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

**Manual Import** opens a dialog for typing devices in one row at a time. Pressing Enter in the Product ID field adds another row. Rows are validated as they are entered, and the Add button stays disabled until every problem is resolved.

Each row must satisfy the following:

* Serial numbers must be unique within the batch.
* Product IDs must be unique within the batch, and exactly 13 characters where supplied.
* A row with a serial number must also carry either both manufacturer and model, or a hardware hash.

Devices already in the list can be removed with the Delete Row action.
{% endstep %}

{% step %}
### Extra Options

**Group Name** names the Partner Center device batch the devices are added to. Leaving it blank generates one automatically. Entering the name of a batch that already exists appends the devices to it rather than creating a new one.
{% endstep %}

{% step %}
### Confirmation

Review the tenant, the device list and the batch name, then submit. CIPP waits briefly for Partner Center to finish processing and then reports the outcome for each device individually, including the error code and description where one failed.
{% endstep %}
{% endstepper %}

## Known Issues / Limitations

* Guessing the manufacturer and model from the device's packaging is unreliable. The hardware hash or the Windows product key ID are far more dependable, and some manufacturers print the product key ID on the box.
* CIPP only waits a few seconds for the import job to report back. On a large batch it may give up before Partner Center finishes and returns a message saying the job may still be running. The registration usually completes regardless, so check the Autopilot Devices list about ten minutes later rather than resubmitting.
* Group tags are only submitted when a new device batch is created. Adding devices to a batch name that already exists drops the group tag, and it will need setting afterwards with **Edit Group Tag** on the Autopilot Devices page.
* Validation runs on manually entered rows only. A CSV is loaded without the duplicate, product key length or serial number companion checks being applied, so errors in a file surface as failures from Partner Center at the end rather than at import time.

{% include "../../../../.gitbook/includes/feature-request.md" %}

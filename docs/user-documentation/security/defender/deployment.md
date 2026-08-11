# Defender Deployment

Run this form to stand Microsoft Defender up in one or more tenants in a single pass. It builds the Intune side of a Defender rollout: the connector settings that link Defender to Intune, an antivirus defaults policy, an exclusion policy, and an Attack Surface Reduction policy, each with its own assignment. Every section is optional, so you can deploy just the parts you need, and you can save what you have configured as reusable Intune templates instead of deploying it.

## Action Buttons

<details>

<summary>Save as Template</summary>

Opens a dialog that saves the settings currently on the form as Intune templates rather than deploying them to a tenant. Each section you configured becomes its own template, so a form with an antivirus policy and an ASR policy produces two.

| Field | Description |
| ----- | ----------- |
| Template Name Prefix | Required. Every template produced is named with this prefix followed by the policy it holds, giving names like `Default Defender - AV Policy`. |
| Package (optional) | Groups the templates produced under a package name, so they can be picked up together when building a Standards template. |

{% hint style="info" %}
Saved templates are visible in [list-templates](../../endpoint/mem/list-templates/ "mention").
{% endhint %}

</details>

## Deploying Defender

{% stepper %}
{% step %}
### Tenant Selection

Select one or more tenants to apply the policies. This is a required field, and at least one tenant must be selected.
{% endstep %}

{% step %}
### Defender Setup Options

Turn on **Show Defender Setup Options** to configure how Defender connects to Intune for each device platform, and what happens when it cannot be reached.

#### General

| Setting                                                                                        | Description                                                                                                                              |
| ---------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Allow Microsoft Defender for Endpoint to enforce Endpoint Security Configurations (Compliance) | Lets Defender enforce endpoint security configuration in Intune. <mark style="color:$warning;">Everything else in this step stays greyed out until this is on.</mark> |
| Block unsupported OS versions                                                                  | Blocks devices with unsupported OS versions from connecting.                                                                             |

#### Android

| Setting                                                                                                 | Description                                                                                                                           |
| ------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Connect Android devices to Microsoft Defender for Endpoint                                              | Connects Android devices to Defender. <mark style="color:$warning;">The rest of this section stays greyed out until this is on.</mark> |
| Connect Android devices version 6.0.0 and above to Microsoft Defender for Endpoint (MAM)                | Enables app protection policy evaluation for Android 6.0 and above.                                                                   |
| Block Android device access when Microsoft Defender for Endpoint is unavailable                         | Blocks Android device access if Defender is unreachable.                                                                              |
| Grant MTD role permissions to Microsoft Defender for Endpoint on enrolled Android COBO and COPE devices | Grants Defender for Endpoint the Mobile Threat Defense partner role on Android corporate owned enrolled devices.                      |

#### macOS

| Setting                                                                     | Description                                                                                                                         |
| --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| Connect Mac devices to Microsoft Defender for Endpoint                      | Connects macOS devices to Defender. <mark style="color:$warning;">The rest of this section stays greyed out until this is on.</mark> |
| Block Mac device access when Microsoft Defender for Endpoint is unavailable | Blocks Mac device access if Defender is unreachable.                                                                                |

#### EDR Policy

| Setting                                                                  | Description                                                                                                                                                            |
| ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| EDR: Connect Defender Configuration Package automatically from Connector | Pulls the Defender onboarding package from the connector automatically. <mark style="color:$warning;">The rest of this section stays greyed out until this is on.</mark> |
| EDR: Enable Sample Sharing                                               | Enables sharing of file samples for analysis.                                                                                                                          |
| Assignment                                                               | Who the EDR policy is assigned to: Do not assign, Assign to all users, Assign to all devices, or Assign to all users and devices.                                       |

#### iOS / iPadOS

| Setting                                                                        | Description                                                                                                                              |
| ------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Connect iOS/iPadOS devices to Microsoft Defender for Endpoint                  | Connects iOS and iPadOS devices to Defender. <mark style="color:$warning;">The rest of this section stays greyed out until this is on.</mark> |
| Connect iOS/iPadOS devices for app protection policy evaluation (MAM)          | Enables app protection policy evaluation for iOS and iPadOS.                                                                             |
| Enable App Sync (sending application inventory) for iOS/iPadOS devices         | Sends application inventory for iOS and iPadOS devices to Defender.                                                                      |
| Send full application inventory data on personally-owned iOS/iPadOS devices    | Extends application inventory to personally owned devices. Greyed out until **Enable App Sync** is on.                                    |
| Block iOS device access when Microsoft Defender for Endpoint is unavailable    | Blocks iOS device access if Defender is unreachable.                                                                                     |
| Enable Certificate Sync for iOS/iPadOS devices                                 | Sends certificate inventory for iOS and iPadOS devices to Defender.                                                                      |
| Send full certificate inventory data on personally-owned iOS/iPadOS devices    | Extends certificate inventory to personally owned devices. Greyed out until **Enable Certificate Sync** is on.                            |

#### Windows

| Setting                                                                                              | Description                                                                                                                                                |
| ---------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Connect Windows devices version 10.0.15063 and above to Microsoft Defender for Endpoint (Compliance) | Connects Windows 10 build 15063 and above for compliance. <mark style="color:$warning;">The rest of this section stays greyed out until this is on.</mark> |
| Connect Windows devices to Microsoft Defender for Endpoint (MAM)                                     | Enables app protection policy evaluation for Windows.                                                                                                      |
| Block Windows device access when Microsoft Defender for Endpoint is unavailable                      | Blocks Windows device access if Defender is unreachable.                                                                                                   |
{% endstep %}

{% step %}
### Defender Defaults Policy Options

Turn on **Show Defender Defaults Policy Options** to build an antivirus policy covering scanning behavior, cloud protection, update handling and what Defender does when it finds something.

#### Defender Defaults Policy

| Setting                             | Description                                                                                                                                             |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Allow Archive Scanning              | Enables scanning inside archive files such as zip and cab.                                                                                              |
| Allow behavior monitoring           | Enables monitoring of application behavior for suspicious activity.                                                                                    |
| Allow Cloud Protection              | Enables cloud based protection for faster threat intelligence.                                                                                          |
| Allow e-mail scanning               | Enables scanning of email content and attachments.                                                                                                      |
| Allow Full Scan on Network Drives   | Enables full scans on mapped network drives.                                                                                                            |
| Allow Full Scan on Removable Drives | Enables full scans on removable and USB drives.                                                                                                         |
| Allow Script Scanning               | Enables scanning of scripts before execution.                                                                                                           |
| Enable Low CPU priority             | Reduces CPU priority for Defender scans to minimise impact.                                                                                             |
| Allow Metered Connection Updates    | Allows Defender definition updates over metered connections.                                                                                            |
| Disable Local Admin Merge           | Prevents local admin policy from merging with enterprise policy.                                                                                        |
| Avg CPU Load Factor(%)              | The maximum average CPU usage for scans, from 0 to 100. Defaults to 50 if left empty.                                                                   |
| Allow On Access Protection          | Controls real time on access file scanning. Options: Not Allowed, Allowed (Default).                                                                    |
| Submit Samples Consent              | Controls automatic sample submission. Options: Always prompt, Send safe samples automatically (Default), Never send, Send all samples automatically.     |
| Allow scanning of downloaded files  | Enables scanning of files downloaded from the internet.                                                                                                 |
| Allow Realtime monitoring           | Enables real time monitoring of files and processes.                                                                                                    |
| Allow Scanning Network Files        | Enables scanning of files on mapped network drives.                                                                                                     |
| Allow users to access UI            | Allows end users to access the Defender user interface.                                                                                                 |
| Check Signatures before scan        | Verifies signatures before initiating a scan.                                                                                                           |
| Signature Update Interval (hours)   | How often Defender checks for definition updates, from 0 to 24. Defaults to 8 if left empty.                                                             |
| Disable Catchup Full Scan           | Disables scheduled catchup full scans for endpoints that missed a scan.                                                                                 |
| Disable Catchup Quick Scan          | Disables scheduled catchup quick scans for endpoints that missed a scan.                                                                                |
| Cloud Extended Timeout (seconds)    | How long Defender waits for a cloud response, from 0 to 50. Defaults to 0 if left empty.                                                                 |
| Enable Network Protection           | Options: Disabled (Default), Enabled (block mode), Enabled (audit mode).                                                                                |
| Cloud Block Level                   | Options: Default, High, High Plus, Zero Tolerance.                                                                                                      |

#### Threat Remediation Actions

Set what Defender does with a detection, separately for **Low severity threats**, **Moderate severity threats**, **High severity threats** and **Severe threats**. All four offer the same choices.

| Option | Description |
| ------ | ----------- |
| Clean | Service tries to recover files and try to disinfect. |
| Quarantine | Moves files to quarantine. |
| Remove | Removes files from system. |
| Allow | Allows file, and does none of the above actions. |
| User defined | Requires user to make a decision on which action to take. |
| Block | Blocks file execution. |

#### Policy Assignment

Who the antivirus policy is assigned to: Do not assign, Assign to all users, Assign to all devices, or Assign to all users and devices.
{% endstep %}

{% step %}
### Exclusion Policy

Turn on **Show Exclusion Policy Options** to build a policy that keeps Defender away from specific extensions, paths and processes. Each of the three lists is built entry by entry: select the add button to create a row, type the value, and use the remove icon beside a row to drop it.

| Setting             | Description                                                                                   |
| ------------------- | --------------------------------------------------------------------------------------------- |
| Excluded Extensions | File extensions to exclude from scanning, one per row, for example `txt`, `log` or `tmp`.      |
| Excluded Paths      | File and folder paths to exclude, one per row, for example `C:\temp`.                          |
| Excluded Processes  | Processes to exclude, one per row, for example `notepad.exe`.                                  |
| Assign to Group     | Who the exclusion policy is assigned to: Do not assign, Assign to all users, Assign to all devices, or Assign to all users and devices. |

{% hint style="warning" %}
Exclusions apply to every device the policy is assigned to. Excluding a broad path or a commonly abused process creates a blind spot that malware can be dropped into, so keep the lists as narrow as the application actually requires.
{% endhint %}
{% endstep %}

{% step %}
### ASR

Turn on **Show ASR Options** to build an Attack Surface Reduction policy. Pick a **Mode** for the policy, then turn on the rules you want it to carry.

| Setting | Description |
| ------- | ----------- |
| Mode    | How every rule in the policy behaves: Block mode, Audit mode, or Warn mode. |

{% hint style="info" %}
The mode applies to the whole policy rather than to individual rules. Deploying in **Audit mode** first shows you what each rule would have blocked, which is the safer way to introduce ASR into a tenant you do not know well.
{% endhint %}

#### ASR Rules

| Setting                                                                                           | Description                                                                                                                                                                                                                |
| ------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Block execution of potentially obfuscated scripts                                                 | Detects suspicious properties within obfuscated scripts, such as heavily encoded or scrambled code, and blocks execution. Targets malware that uses obfuscation to evade detection.                                        |
| Block Adobe Reader from creating child processes                                                  | Prevents Adobe Reader from spawning child processes. This is a common technique used to execute malicious code through PDF files. Applies to all versions of Adobe Reader.                                                 |
| Block Win32 API calls from Office macros                                                          | Prevents Office VBA macros from making Win32 API calls, which are frequently used in macro based malware to execute shellcode or download payloads.                                                                        |
| Block credential stealing from the Windows local security authority subsystem                     | Prevents credential dumping from LSASS, blocking tools that extract passwords and hashes from memory.                                                                                                                      |
| Block process creations originating from PSExec and WMI commands                                  | Blocks process creation via PSExec and WMI, which are commonly used in lateral movement and remote execution attacks. This can affect legitimate admin tooling.                                                            |
| Block persistence through WMI event subscription                                                  | Prevents malware from using WMI event subscriptions to maintain persistence across reboots. Targets fileless malware that uses WMI as an execution and persistence mechanism.                                              |
| Block use of copied or impersonated system tools                                                  | Blocks use of copies or renamed versions of legitimate Windows system tools, such as `cmd.exe` or `powershell.exe` copied to another location, commonly used to evade detection.                                           |
| Block Office applications from creating executable content                                        | Prevents Word, Excel and PowerPoint from writing executable files to disk, blocking a common macro malware delivery technique.                                                                                             |
| Block Office applications from injecting code into other processes                                | Prevents Office applications from injecting code into other running processes, which is used by some exploit techniques to execute malicious code under a trusted process.                                                 |
| Block rebooting machine in Safe Mode                                                              | Prevents attackers from rebooting the device into Safe Mode, a technique used by some ransomware families to disable security tools before encrypting files.                                                               |
| Block executable files from running unless they meet a prevalence, age, or trusted list criterion | Blocks executable files that are new, rarely seen, or not on a trusted list. Uses cloud intelligence to evaluate file reputation before allowing execution. Can generate false positives for legitimate but rare software. |
| Block JavaScript or VBScript from launching downloaded executable content                         | Prevents JavaScript and VBScript files, frequently used as malware droppers, from downloading and executing binaries. Targets drive by download attacks.                                                                   |
| Block Webshell creation for Servers                                                               | Prevents the creation of web shell scripts on servers. Targets post exploitation persistence where attackers drop scripts into web accessible directories to maintain remote access.                                       |
| Block Office communication application from creating child processes                              | Prevents Outlook, Teams and other Office communication apps from spawning child processes. Targets phishing based attacks that exploit these applications.                                                                 |
| Block all Office applications from creating child processes                                       | Blanket block on child process creation from any Office application. Broader than the communication app rule, covering Word, Excel, PowerPoint and others.                                                                 |
| Block untrusted and unsigned processes that run from USB                                          | Prevents execution of untrusted or unsigned binaries from USB and removable devices. Helps mitigate attacks delivered via physical media.                                                                                  |
| Use advanced protection against ransomware                                                        | Enables heuristic ransomware detection in addition to signature based protection. Analyzes file behavior patterns associated with ransomware activity.                                                                    |
| Block executable content from email client and webmail                                            | Prevents executable files and scripts from being launched directly from email clients and webmail. Targets phishing attachments.                                                                                           |
| Block abuse of exploited vulnerable signed drivers (Device)                                       | Prevents malware from using legitimately signed but vulnerable drivers, sometimes described as bring your own vulnerable driver, to gain kernel level access and disable security software.                                 |
| Assign to Group                                                                                   | Who the ASR policy is assigned to: Do not assign, Assign to all users, Assign to all devices, or Assign to all users and devices.                                                                                          |
{% endstep %}
{% endstepper %}

For more details on each setting, refer to the [Microsoft Defender for Endpoint documentation](https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/microsoft-defender-endpoint?view=o365-worldwide).

{% include "../../../../.gitbook/includes/feature-request.md" %}

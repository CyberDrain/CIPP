---
description: Where the Huntress or CIPP Rogue Apps alert gets its list of applications.
---

# Rogue Apps

The scripted alert **Alert on Huntress or CIPP Rogue Apps detected** checks the enterprise applications (service principals) present in each selected tenant against a list of applications that have been observed being abused by threat actors against Microsoft 365 tenants. Because the alert draws from two lists, it can report applications that do not appear on the Huntress website.

## Where the list comes from

Each time the alert runs, the list is built from two sources:

* **The Huntress RogueApps feed** - The community-maintained repository published by Huntress at [https://huntresslabs.github.io/rogueapps/](https://huntresslabs.github.io/rogueapps/).
* **The CIPP curated list** - Applications collected by the CIPP team and community from incident write-ups and threat intelligence. This list ships with CIPP and is updated with CIPP releases.

The two lists overlap. When an application appears in both, it is reported once, with the details from the Huntress feed. The **Source** field on each alert result shows which list the application came from: `Huntress` or `CIPP`.

{% hint style="info" %}
If the Huntress feed is temporarily unreachable, the check skips that run rather than alerting on partial data, and picks up again on the next scheduled run.
{% endhint %}

## What a detection means

A match means a service principal for the application exists in the tenant, which happens when a user or administrator has consented to it at some point. It does not automatically mean the tenant is compromised: several listed applications are legitimate products that threat actors abuse after gaining access to an account. Treat a detection as a prompt to verify whether the consent was expected, review the sign-in and audit logs for the application, and revoke the service principal if it was not.

The alert's **Ignore Disabled Apps?** option skips service principals that are already disabled, so only applications that can still be used are reported.

## Applications on the CIPP curated list

| Application                     | App ID                                 | Why it is listed                                                                                                    |
| ------------------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| CloudSponge                     | `a43e5392-f48b-46a4-a0f1-098b5eeb4757` | Contact-import service abused to harvest address books.                                                              |
| CubeBackup                      | `412445a2-0794-487e-9dd6-d57d9593b249` | Microsoft 365 backup tool abused for mass mailbox, SharePoint and OneDrive exfiltration.                             |
| Edison Mail                     | `62db40a4-2c7e-4373-a609-eda138798962` | Email client with full mailbox synchronisation, abused for mailbox exfiltration.                                     |
| eM Client                       | `e9a7fea1-1cc0-4cd9-a31b-9137ca5deedd` | Desktop email client abused to bulk-synchronise compromised mailboxes and maintain access.                           |
| Fastmail                        | `77468577-4f6e-40e7-b745-11d3d0c28095` | Email service whose import feature can exfiltrate all mail to an attacker-controlled account.                        |
| Foxmail                         | `231575bc-9f6c-4539-9241-5cfae696b630` | Desktop email client observed in business email compromise with full legacy-protocol mailbox access.                 |
| Horizon Tech                    | `b1c4926a-5fb6-4aad-b920-709c957be148` | Pulls email and contacts and sends phishing from the compromised mailbox.                                            |
| Jotform                         | `9af771d1-1288-43f0-91a6-adadcbd212b5` | Online form builder abused as a native phishing and spam vector after Microsoft 365 SSO consent.                     |
| Mail_Backup                     | `2ef68ccc-8a4d-42ff-ae88-2d7bb89ad139` | Mailbox export tool used to exfiltrate email. Renamed successor to PerfectData Software.                             |
| Newsletter Software Supermailer | `a245e8c0-b53c-4b67-9b45-751d1dff8e6b` | Bulk email tool abused to send phishing and spam from a compromised mailbox.                                         |
| PerfectData Software            | `ff8d92dc-3d82-41d6-bcbd-b9174d163620` | Mailbox export tool widely abused in business email compromise to bulk-export victim mailboxes.                      |
| PostBox                         | `179d5108-412b-4c95-8e34-06786784ab39` | Desktop email client abused for mailbox exfiltration and persistence.                                                |
| rclone                          | `4761b959-9780-4c2d-87a3-512b4638f767` | Command-line cloud storage tool abused to bulk-download SharePoint and OneDrive content.                             |
| SigParser                       | `caffae8c-0882-4c81-9a27-d1803af53a40` | Email-scanning contact intelligence tool abused for address book harvesting.                                         |
| Spike                           | `946c777c-bc85-489e-b034-392389ae23d6` | Conversational email client abused for mailbox exfiltration, persistence and phishing.                               |
| Teleforge Directory             | `1a9b8d93-0d60-4835-896f-83016de95ff5` | Observed in business email compromise, collecting mailbox data before fraudulent email was sent.                     |
| ZoomInfo Communitiez Login      | `497ac034-5120-4c1a-929a-0351f5c09918` | Created by ZoomInfo's My Connections feature, which extracts contacts for target discovery and phishing.             |
| Zoominfo Login                  | `858d7e42-35f0-44b7-9033-df309239a47f` | ZoomInfo SSO sign-in service principal, abused for persistence and contact harvesting.                               |

The authoritative copy of this list is the `Config/MaliciousApps.json` file shipped with your CIPP version, which also carries the permissions, references and detection guidance for each entry. New applications are added as they are observed in the wild, so the table above may trail the list in a recent release.

{% include "../../../../../.gitbook/includes/feature-request.md" %}

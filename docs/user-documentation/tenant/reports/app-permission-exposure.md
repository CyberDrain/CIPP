# App Permission Exposure

This report lists every application in the selected tenant that holds a permission, directory role or Exchange application role from CIPP's curated set of risky permissions, and rates how exposed the tenant is through each one. It is built to answer two questions quickly: which applications could do the most damage if they were compromised, and which look out of place for what they hold.

Each application is rated on two scales and a combined risk:

* **Impact**: how much damage the application could do if it were compromised, from Low to Critical. The highest impact among everything it holds sets the application's rating. A directory role or Exchange application role limited to an administrative unit or management scope counts one step lower, as do mailbox permissions an Exchange application access policy restricts to a group of mailboxes.
* **Suspicion**: how unusual it is for an application to hold what this one holds, adjusted for who owns it and how it looks in this tenant. Suspicion rises for a credential added to the application recently, added by another application, or dated earlier than when it was added, for a federated credential that lets an identity provider CIPP does not recognise or another organisation's Entra tenant sign in as the application, for consent or a role granted in the last few days, and for an application owned by another organisation. It rises further when a recently added credential has already signed in, when Identity Protection rates the application at high or medium risk, for an application owned elsewhere that is named like a Microsoft product without a verified publisher, for a redirect URI on plain http, a raw IP address or a tunnelling service, and for an application registered here that is owned by a guest account or another application. Suspicion is Critical when Microsoft has disabled the application, or an administrator has confirmed it compromised in Identity Protection. Microsoft first-party applications and CIPP's own application are rated Low unless their service principal holds a sign-in credential, which neither Microsoft nor CIPP adds, so that rates them Critical.
* **Risk**: impact and suspicion combined. A disabled application is rated Low risk, because it cannot sign in or obtain tokens until it is enabled again.

Hover the **Risk** chip in a row to see every reason that went into the rating.

{% hint style="info" %}
The report covers one tenant at a time, so select a specific tenant rather than **All Tenants**.
{% endhint %}

## Filters

| Filter                                             | Shows                                                                                          |
| -------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Critical risk                                      | Applications rated Critical risk.                                                              |
| High risk                                          | Applications rated High risk.                                                                  |
| Critical impact                                    | Applications whose highest impact is Critical.                                                 |
| Tenant-wide data access (vendor breach exposure)   | Applications with Critical impact that can read data such as mail, files or chats.             |
| Privilege escalation                               | Applications that can give themselves or others more access.                                   |
| Critical suspicion                                 | Applications rated Critical suspicion.                                                         |
| Stale apps (no sign-in for 90+ days)               | Applications that last signed in more than 90 days ago.                                        |
| Apps with no sign-in recorded                      | Applications with no sign-in on record.                                                        |
| MSP vendor apps                                    | Applications owned by a known MSP tool vendor.                                                 |
| Other known vendor apps                            | Applications owned by another known vendor.                                                    |
| Third-party apps                                   | Applications owned by another organisation that CIPP does not recognise.                       |
| Apps registered with a personal Microsoft account  | Applications registered by someone using a personal Microsoft account.                         |
| Apps owned by this tenant                          | Applications registered in this tenant.                                                        |
| Microsoft apps                                     | Microsoft first-party applications.                                                            |
| Managed identities                                 | Managed identities belonging to Azure resources.                                               |

## Table Details

| Column                  | Description                                                                                                                                                                                                          |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| App Display Name        | The application's name in the tenant.                                                                                                                                                                                |
| Risk                    | The combined rating, from Low to Critical. Hover it for the reasons behind it.                                                                                                                                       |
| Highest Impact          | The highest impact among everything the application holds. Hover it for what the level means.                                                                                                                        |
| Categories              | What the application's risky permissions let it do: **Privilege escalation**, **Data access**, **Integrity** (create or change data or configuration) and **Availability** (delete or disable objects). Hover a chip for its meaning. |
| Ownership               | Who owns the application: `Microsoft`, `This tenant`, `Partner tenant`, `MSP vendor`, `Known vendor`, `Third party`, `Personal account`, `Managed identity`, or `Unknown`. Hover it for the owner's tenant ID.          |
| Vendor                  | The vendor CIPP recognises as the owner, where there is one. Hover it for the vendor's company, website, type and category, and whether GDAP offboarding offers the application for removal.                         |
| Vendor Category         | The kind of product the recognised vendor makes.                                                                                                                                                                     |
| Publisher Name          | The publisher recorded against the application.                                                                                                                                                                      |
| Verified Publisher      | The verified publisher, where the application has one.                                                                                                                                                               |
| Account Enabled         | Whether the application can sign in and obtain tokens in this tenant.                                                                                                                                                |
| Sign In Activity        | `Active` (signed in within 30 days), `Idle 30+ days`, `Stale 90+ days`, `No sign-in recorded`, or `Unknown` where sign-in activity has not been collected. Hover it for the last sign-in of each kind.                |
| Last Sign In Date Time  | The application's most recent sign-in of any kind.                                                                                                                                                                   |
| Permission Count        | How many risky permissions and roles the application holds.                                                                                                                                                          |
| Directory Role Count    | How many Microsoft Entra directory roles the application holds, directly or through a role-assignable group.                                                                                                         |
| Has All Principals Grant | Whether a delegated permission has been consented for every user in the tenant, rather than by individual users.                                                                                                    |
| App Id                  | The application (client) ID.                                                                                                                                                                                         |

{% hint style="info" %}
Sign-in activity needs Microsoft Entra ID P1 in the tenant. Without it, **Sign In Activity** shows `Unknown`.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View in CIPP</td><td>Opens the <a data-mention href="../administration/applications/enterprise-apps/spid.md">spid.md</a> page for the selected application.</td><td>false</td></tr><tr><td>Investigate compromise</td><td>Opens the application on the <a href="../administration/nhi/case.md">NHI Case</a> page and starts a compromise investigation of it. Greyed out while <strong>All Tenants</strong> is selected.</td><td>false</td></tr><tr><td>Disable Service Principal</td><td>Stops sign-ins and token issuance for the application in this tenant. Its permissions stay in place and it can be enabled again. Greyed out unless the application is enabled, and for CIPP's own application.</td><td>true</td></tr><tr><td>Enable Service Principal</td><td>Allows a disabled application to sign in and obtain tokens again. Greyed out unless the application is disabled.</td><td>true</td></tr><tr><td>Delete Service Principal</td><td>Removes the application and every permission granted to it from this tenant. Using the application again needs a new consent. You are asked to type <code>DELETE</code> to confirm. Greyed out for CIPP's own application.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
Disable, Enable and Delete need the `Tenant.Application.ReadWrite` permission, and are greyed out without it.
{% endhint %}

The flyout shows the application's ratings, ownership, vendor details, sign-in activity of each kind, credential and permission counts, whether Microsoft has disabled it, its Identity Protection risk, and the owners who can add credentials to it, with the reasons for its risk rating. A **Disabled by Microsoft** chip marks an application Microsoft has disabled. Beneath them, tables list its credentials, with when each last signed in and any flags raised against it, directory roles, Exchange application roles and each risky permission, with the impact, suspicion and reason for each, and when and by whom it was added where that is known. For a third-party application that can read data across the tenant, a warning explains that a breach at the vendor would give an attacker that access without any change in this tenant.

{% hint style="warning" %}
Disabling or deleting an application breaks anything that relies on it. CIPP's own application is marked **CIPP** in the flyout: it needs the permissions it holds to manage the tenant.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

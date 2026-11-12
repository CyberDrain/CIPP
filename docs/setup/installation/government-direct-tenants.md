# GCC High and DoD Direct Tenants

CIPP can sign in to a GCC High or DoD tenant as a **direct tenant** (the per-tenant authentication in the Tenant Onboarding wizard). These tenants live in Azure Government, which has its own sign-in authority (`login.microsoftonline.us`) and Microsoft Graph hosts (`graph.microsoft.us` for GCC High, `dod-graph.microsoft.us` for DoD). An app registered in the commercial cloud, such as CIPP-SAM, cannot be consented in them, so CIPP uses a second app that you register in Azure Government.

{% hint style="info" %}
GCC (Moderate) tenants run on the commercial cloud. Add them as **Commercial / GCC**; they do not need the Azure Government app.
{% endhint %}

{% hint style="warning" %}
CIPP sends a government tenant's requests to that cloud's hosts: Microsoft Graph, Exchange Online (`outlook.office365.us` for GCC High, `webmail.apps.mil` for DoD), the Office 365 Management API, Defender for Endpoint and SharePoint. Features built on services with no documented government endpoint CIPP can use - Teams policies, Security & Compliance (Purview) PowerShell, Partner Center, the classic admin APIs and MFA push notifications - return a "not supported for government tenants" error. So do features Microsoft Graph in Azure Government does not have (for example Copilot admin settings) and JIT Admin. Their pages are hidden while a government tenant is selected, and their standards, alerts and scheduled jobs skip government tenants. The automatic permission push is skipped for government tenants, so you add the app's permissions yourself (step 1).
{% endhint %}

## 1. Register the Azure Government app

1. Sign in to the Azure Government portal (`https://portal.azure.us`) with an account in a GCC High or DoD tenant you control, and open **Microsoft Entra ID > App registrations > New registration**.
2. Name it (for example `CIPP-Gov`) and choose **Accounts in any organizational directory (Multitenant)**.
3. Under **Redirect URI**, choose **Web** and enter `https://<your CIPP address>/authredirect`. The Credentials page in CIPP shows the exact value.
4. Under **API permissions**, add the permissions CIPP uses (see [Permissions](#permissions) below): the same Microsoft Graph permissions as CIPP-SAM, delegated **and** application, plus the Exchange Online and Defender for Endpoint permissions for those features. The tenant administrator consents to them when adding the tenant.
5. Under **Certificates & secrets**, add the credential CIPP will use (step 2): the certificate CIPP generates, or a client secret. If certificate authentication is turned on for your CIPP instance, only the certificate is used.

### Permissions

CIPP pushes CIPP-SAM's permissions into GDAP tenants automatically, but that push is skipped for government tenants, so the Azure Government app must already have everything CIPP calls. Some pages call Microsoft Graph as the signed-in admin and some call it app-only, so add both the **delegated** and the **application** permissions.

**Microsoft Graph.** Use the Microsoft Graph entry (`resourceAppId` `00000003-0000-0000-c000-000000000000`) of CIPP-SAM's manifest, `backend/Config/SAMManifest.json` in the CIPP repository. You cannot paste it into the government app as it is: Microsoft Graph in Azure Government uses different ids for some permissions and does not have others. Checked against GCC High on 2026-11-11, 29 of the manifest's Graph permission ids differ and these 6 do not exist:

| Permission | Type |
| --- | --- |
| `RoleManagement.ReadWrite.Exchange` | Application |
| `TeamsUserConfiguration.Read.All` | Application and delegated |
| `ThreatSubmission.ReadWrite.All` | Application |
| `DelegatedAdminRelationship.ReadWrite.All` | Delegated |
| `RoleManagement.Read.Exchange` | Delegated |

Match each permission **by name** (and type) against the Microsoft Graph service principal in Azure Government. `build/tools/New-CippGovAppPermissions.ps1` does this from a JSON export of that service principal and prints the permissions it had to skip:

```powershell
az cloud set --name AzureUSGovernment
az login   # an account in the GCC High or DoD tenant that owns the app
az rest --uri "https://graph.microsoft.us/v1.0/servicePrincipals(appId='00000003-0000-0000-c000-000000000000')?`$select=appId,appRoles,oauth2PermissionScopes" > govgraph.json
./build/tools/New-CippGovAppPermissions.ps1 -ServicePrincipalPath ./govgraph.json -OutFile ./gov-graph-permissions.json
```

For DoD use `https://dod-graph.microsoft.us`. In the app registration's **Manifest**, replace the `requiredResourceAccess` item whose `resourceAppId` is `00000003-0000-0000-c000-000000000000` with the content of `gov-graph-permissions.json` (keep the other items), and save. The script only reads the three files; it does not sign in or change anything.

**Other services.** Add these by name from the same API in the **APIs my organization uses** list. They only work where the tenant is licensed for the service:

* **Office 365 Exchange Online**: `Exchange.Manage`, `Calendars.ReadWrite.All` and `MailboxSettings.ReadWrite` (delegated); `Exchange.ManageAsApp`, `Calendars.ReadWrite.All` and `MailboxSettings.ReadWrite` (application). Needed for mailboxes, transport rules and the other Exchange pages.
* **WindowsDefenderATP**: `Vulnerability.Read` (delegated) and `Vulnerability.Read.All` (application). Needed for Defender for Endpoint vulnerability data; the tenant needs a Defender for Endpoint licence.
* CIPP-SAM also has Office 365 SharePoint Online (`AllSites.FullControl`; `Sites.FullControl.All`, `User.ReadWrite.All`) and Office 365 Management APIs (`ActivityFeed.Read`) permissions. Add them if you use the SharePoint pages or audit log alerts with government tenants.

Partner Center and the Skype and Teams Tenant Admin API are not needed: CIPP does not call them for government tenants.

**Consent.** After changing the permissions, select **Grant admin consent** in each government tenant (or sign in to the tenant again from CIPP and consent). Tenants that are already added pick up the new permissions with the next access token CIPP requests for them, so you do not need to remove and re-add them. Allow a few minutes, and up to about an hour while tokens CIPP has already cached for the tenant expire.

## 2. Enter the app in CIPP

Go to **CIPP > Advanced > Authentication > Credentials**. In the **Azure Government app (GCC High / DoD)** card:

1. Enter the **Application (client) ID** and select **Save**. Generating a certificate does not save the ID, and the card warns you while an ID is unsaved.
2. Add a credential:
   * **Certificate:** select **Generate certificate**, then **Download certificate**, and upload the `.cer` file to the app registration. CIPP keeps the private key in Key Vault. Compare the thumbprint shown in the card with the one in the app registration.
   * **Client secret:** enter it and select **Save**. It is stored in Key Vault next to the CIPP-SAM secret and is never shown again.

The **Signs in with** row shows which credential CIPP will use. It uses the certificate when certificate authentication is turned on for the instance, or when no client secret is stored, and the client secret otherwise. When certificate authentication is on, the client secret field is disabled because a secret would not be used.

The **Redirect URI** row shows the exact value to register: your CIPP address followed by `/authredirect`.

Changing these values needs the `CIPP.AppSettings.ReadWrite` permission **and** unrestricted tenant access (all tenants), the same as adding a tenant. Viewing the card's status only needs `CIPP.AppSettings.ReadWrite`.

{% hint style="warning" %}
**Generate new certificate** replaces the stored certificate immediately. If the instance signs in with the certificate, government tenants fail until you upload the new `.cer` to the app registration.
{% endhint %}

## 3. Add the tenant

In the Tenant Onboarding wizard, under per-tenant authentication, choose **GCC High** or **DoD** as the tenant cloud and select **Connect to Tenant**. Sign in with an administrator of the government tenant and consent. CIPP checks that the sign-in token belongs to the chosen cloud and that the tenant's public discovery data agrees before it adds the tenant.

If the Azure Government app is not configured, government tenants fail with "Azure Government app not configured". CIPP never uses the CIPP-SAM credentials for them.

## Partner tenant cloud

GDAP does not work across clouds, so your partner tenant, every GDAP tenant and CIPP-SAM are always in the same cloud. CIPP assumes that is the commercial cloud. If your partner tenant is in GCC High or DoD, set the Function App application setting `CIPP_PARTNER_CLOUD` to `USGovHigh` or `USGovDoD` (exact case) and restart the app. Leave it unset, or set it to `Commercial`, otherwise. Any other value stops CIPP from requesting tokens until it is corrected.

Tenants that already have a cloud stored keep it. To change one, use **Set Cloud Environment** on the tenants page (Tenant Administration > Tenants). A direct tenant cannot be moved between Commercial and GCC High or DoD this way, in either direction: its stored sign-in was issued by the cloud it was added in and only works there. Remove the tenant and add it again in the new cloud instead. Moving a direct tenant between GCC High and DoD is allowed, because they share a sign-in authority. Tenants that are not direct tenants can be changed freely.

## Portal links

For a GCC High or DoD tenant, CIPP's links to Microsoft admin portals open the government portals: Azure (`portal.azure.us`), Entra (`entra.microsoft.us`), Intune (`intune.microsoft.us`), Defender (`security.microsoft.us`, or `security.apps.mil` for DoD) and Power Platform. Links to portals with no documented government address, such as the Microsoft 365, Exchange and Teams admin centers, Purview and Power BI, are not shown for these tenants. Sign in to those portals directly with an account from the government tenant.

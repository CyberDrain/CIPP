# Permissions

The Permissions page verifies that CIPP has the access it needs to manage your tenants. It runs three checks: one covering CIPP's own application registration and service account, one covering your GDAP relationships, and one that tests access to each tenant individually. Some problems can be fixed from the page itself, and the rest point you to the change to make elsewhere. The results can be exported as a diagnostic report for troubleshooting or support. Where your tenants are added directly rather than through Microsoft Partner Center relationships, the GDAP check does not apply and access is confirmed per tenant by the Tenants check instead.

## Diagnostic Report

The buttons at the top of the page export the current check results, or load a report that was exported elsewhere. This is intended for troubleshooting and for sharing results with support.

| Action                | Description                                                                                                                                                                       |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Export Report         | Exports the current permissions, GDAP, and tenant results as a JSON file. A Redact Customer Data option is offered, which removes identifying tenant information from the export. |
| Import Report         | Loads a previously exported JSON report from a file so its results can be reviewed on this page.                                                                                  |
| Import from Clipboard | Loads a previously exported report directly from the clipboard rather than from a file.                                                                                           |
| Close report          | Clears the imported report and returns the page to live results.                                                                                                                  |

While an imported report is being viewed, each affected check is marked with an "Imported" label and its Refresh button is disabled, since the results come from the file rather than from your environment. The repair buttons described below are not offered for imported results either.

## Permissions Check

Checks the account and application CIPP signs in with, and the permissions granted to that application. Select **Refresh** to run the check again without using cached results, or **Details** to open the Permission Details flyout with the full breakdown. The time of the last run is shown beside the buttons.

The card lists each result with a tick, a warning, or a cross. When everything passes, the card ends with "No service account issues have been found. CIPP is ready for use."

| Result                         | What a failure means and how to fix it                                                                                                                                                                                                                                                                         |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Service account                | CIPP does not appear to be signed in as a dedicated service account. Use a dedicated account for CIPP and refresh your tokens in the [SAM Setup Wizard](../sam-setup-wizard.md). The Details flyout links to the guide for creating one.                                                                        |
| MFA claim                      | The sign-in CIPP is using did not complete multi-factor authentication. Refresh your tokens in the [SAM Setup Wizard](../sam-setup-wizard.md), completing MFA as the service account.                                                                                                                          |
| Device code login              | The token CIPP holds was first obtained through a device code sign-in, which Conditional Access blocks in some customer tenants. Refresh your token in the [SAM Setup Wizard](../sam-setup-wizard.md). Where CIPP cannot read your sign-in logs to check this, the card says so instead of reporting a failure. |
| Refresh token                  | The token CIPP is currently using does not match the one that is stored. This happens shortly after a token refresh and resolves itself within thirty minutes.                                                                                                                                                 |
| Application secret             | The secret CIPP authenticates with as its own application has expired, or is close to expiry. See [Application secret](#application-secret).                                                                                                                                                                   |
| New permissions to apply       | A CIPP update needs permissions that have not been applied yet. Fixed from the page with **Repair Permissions**. See [New permissions to apply](#new-permissions-to-apply).                                                                                                                                      |
| Permissions not granted        | CIPP-SAM is missing Microsoft Graph permissions in your own tenant. There is no repair button for this. See [Permissions not granted in your tenant](#permissions-not-granted-in-your-tenant).                                                                                                                 |
| Tenants need a CPV refresh     | Some tenants have not received CIPP's current permissions, or their last attempt failed. Fixed from the page with **Refresh CPV**. See [Tenants needing CPV Refresh](#tenants-needing-cpv-refresh).                                                                                                             |

If the check cannot connect at all, the card reports the error returned and, where your MFA settings let a session be remembered for several days, warns that this can cause authentication problems for the service account.

### Permission Details

The Details flyout shows the account CIPP signed in as, its IP address, and a link to the CIPP-SAM application in the Azure portal. Below that, it shows only the sections that apply to the current results:

| Section                                | Description                                                                                       |
| -------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Documentation                          | Links to guides for the problems found.                                                           |
| Missing Permissions                    | The new permissions waiting to be applied, with a **Repair Permissions** button.                  |
| Permissions not granted in your tenant | The Microsoft Graph permissions not granted to CIPP-SAM in your tenant. This section has no button. |
| Tenants needing CPV Refresh            | The tenants that need their permissions refreshed, with a **Refresh CPV** button.                 |
| Current Delegated Scopes               | The delegated permissions held by the account CIPP signs in as.                                   |
| Current Application Roles              | The application permissions held by CIPP-SAM.                                                     |

### New permissions to apply

When a CIPP update adds permissions, the card reports "There are new permissions to apply" and the Missing Permissions section of the Details flyout lists each one by application, type, and name. CIPP also raises an alert for this, so it reaches your notifications.

1. Select **Details**, review the list, and select **Repair Permissions**. This adds the new permissions to the set CIPP applies.
2. The tenants then appear under Tenants needing CPV Refresh. Select **Refresh CPV** to apply the permissions to them now, or wait for the nightly permission update.
3. Select **Refresh** on the Permissions check and confirm the warning has cleared.

### Tenants needing CPV Refresh

Lists each tenant that has not received CIPP's current permissions, or whose last permission update failed, with the time of its last refresh. Select **Refresh CPV** to update the permissions now rather than waiting for the nightly update. Every tenant that needs it is refreshed, including your own partner tenant, so you do not need to select them. If a refresh is already running, the request is skipped and a message says so.

### Permissions not granted in your tenant

The check also compares the Microsoft Graph permissions CIPP needs with the ones actually granted to the CIPP-SAM application in your own tenant, once for application permissions and once for delegated permissions. Anything missing is reported as a warning rather than a failure, because CIPP keeps working, but the features that use those permissions fail. For example, certificate authentication needs the Application.ReadWrite.All application permission. The Details flyout lists each permission that is not granted.

{% hint style="info" %}
**Repair Permissions** does not appear for this warning. That button adds new permissions to the set CIPP applies, and these permissions are already in that set: CIPP tried to grant them in your tenant and could not.
{% endhint %}

CIPP grants these permissions itself during its nightly permission update, signed in as the CIPP service account. The usual cause is that the service account does not hold a role that is allowed to grant them. To fix it:

1. In Entra, assign the **Privileged Role Administrator** role to the CIPP service account. **Global Administrator** also works. If you use Privileged Identity Management, make the assignment active rather than eligible.
2. Wait for the next nightly permission update. A failed update is retried a day after the last attempt, so this can take up to two nights. To apply it straight away, run **Refresh CPV Permissions** on the \*Partner Tenant row under CIPP > Application Settings > [Tenants](tenants.md). That row is listed only when the partner tenant is included in the tenant list, and the action needs a role with access to it.
3. Select **Refresh** on the Permissions check and confirm the warnings have cleared.

If you would rather not give the service account that role, a Global Administrator can grant the permissions manually:

1. Select the CIPP-SAM link next to **App Registration** in the Details flyout. It opens the application in the Azure portal.
2. Go to **API permissions**. Add any permission listed in the Details flyout that is not shown, choosing **Microsoft Graph** and then Application or Delegated permissions to match the Type column.
3. Select **Grant admin consent** for your tenant and confirm each permission shows as granted.
4. After a few minutes, select **Refresh** on the Permissions check. Newly granted permissions can take a short while to appear.

### Application secret

The check confirms that the secret CIPP authenticates with as its own application is still valid. CIPP renews that secret automatically ahead of its expiry date, so a problem is only reported where the stored secret has already expired, or is within a few weeks of expiring and has not been renewed. Both are reported on the card with the expiry date, and both need attention, because CIPP uses that secret to obtain access to your tenants.

Shortly after a renewal, the check can report that the secret CIPP is currently using does not match the one that is stored. That resolves itself once the new value is picked up, which takes up to thirty minutes. Where the secret cannot be checked at all, the card reports that rather than treating it as a failure.

## GDAP Check

Checks your Granular Delegated Admin Privileges relationships, the groups the CIPP service account belongs to, and the roles they grant. As with the Permissions check, **Refresh** re-runs it and **Details** opens the GDAP Details flyout.

This check is only shown where it applies. In an environment whose tenants are added directly instead of through Partner Center relationships, the card is replaced with a note explaining that GDAP checks do not apply and that access is verified per tenant by the Tenants check below. The check also remains visible when an imported report contains GDAP results.

The card shows counts of warnings, errors, Microsoft Led Transition relationships, and Global Admin relationships, followed by these results:

| Result                                | What a failure means                                                                                                                                                                                                                       |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Partner Center API access             | CIPP-SAM cannot reach the Partner Center API, so GDAP invites and tenant onboarding fail. The Details flyout gives the reason. This usually points to a wider problem with CIPP-SAM's permissions, so start with the Permissions check. |
| AdminAgents group                     | The service account is not a member of the AdminAgents group in your partner tenant.                                                                                                                                                       |
| CIPP Recommended GDAP groups          | The service account is not a member of all 15 of the CIPP recommended GDAP groups. If you migrated to GDAP outside CIPP, this is expected, and the Tenants check shows whether access actually works.                                     |
| Microsoft Led Transition relationships | A tenant has only a Microsoft Led Transition relationship, which is read-only. Migrate that tenant to GDAP.                                                                                                                                |
| Global Admin relationships            | A relationship includes the Global Administrator role, so it cannot be auto-extended.                                                                                                                                                      |
| GDAP role mappings                    | A GDAP role mapping points at a security group that has been deleted or replaced. Fixed from the page with **Repair Role Mappings**.                                                                                                       |

### GDAP Details

| Section                  | Description                                                                                         |
| ------------------------ | --------------------------------------------------------------------------------------------------- |
| GDAP Issues              | Each issue found, with the tenant, whether it is a warning or an error, and a link where one exists. |
| Missing Groups           | The expected groups the service account is not a member of.                                         |
| Role Mapping Group Check | Each GDAP role mapping, the group it points at, and its status.                                     |
| Group Memberships        | The groups the service account belongs to.                                                          |
| Directory Roles          | The directory roles the service account holds.                                                      |

### Repair Role Mappings

Shown on the Role Mapping Group Check when a mapping is Stale or Missing. A Stale mapping points at a group that no longer exists while a group with the expected name does, and the repair points the mapping at that group. A Missing mapping has no matching group, and the repair recreates it. The repair covers your [GDAP roles](../../tenant/gdap-management/roles/README.md) and every saved [GDAP role template](../../tenant/gdap-management/role-templates/README.md), so onboarding and relationship resets use the corrected groups. Select **Refresh** afterwards to confirm the mappings show as valid.

## Tenants Check

Tests access to each tenant in turn and reports what CIPP can reach. Select **Refresh** to re-check every tenant. The checks run in the background, and a message on the card confirms that they have started.

### Table Details

| Column          | Description                                                                                                                                                                                              |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant Name     | The name of the tenant.                                                                                                                                                                                  |
| Tenant Type     | How CIPP connects to the tenant: Direct for a tenant added with its own service account, or GDAP for one reached through a Partner Center relationship.                                                  |
| Service Account | For a direct tenant, the account CIPP authenticated as. Blank for GDAP tenants, which use the partner relationship rather than an account in the tenant.                                                 |
| Last Run        | When the access check last ran for this tenant.                                                                                                                                                          |
| Graph Status    | Whether CIPP could successfully reach Microsoft Graph in the tenant.                                                                                                                                     |
| Exchange Status | Whether CIPP could successfully reach Exchange Online in the tenant. This also fails when Exchange's **Organization Management** role group is missing roles CIPP relies on.                                 |
| Missing Roles   | Any roles CIPP does not currently hold in the tenant. Billing Administrator, Global Reader, and Domain Name Administrator are optional; the rest are required.                                            |
| Assigned Roles  | The roles CIPP holds in the tenant. For a direct tenant these are the roles held by the service account; where that account is a Global Administrator, the roles it grants implicitly are noted as such. |

Selecting a row opens a flyout with further detail, including the tenant ID, default domain name, when the service account last authenticated, and the full results of the Graph and Exchange tests. The Graph test result says whether any missing roles are required or optional.

To fix missing roles on a GDAP tenant, add the role to the tenant's GDAP relationship and its group mapping. On a direct tenant, assign the role to the service account in that tenant. Then select **Check Tenant** on the row.

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Check Tenant</td><td>Re-runs the access check for the selected tenant.</td><td>true</td></tr><tr><td>Repair Exchange Roles</td><td>Adds the roles missing from Exchange's **Organization Management** role group in the selected tenant. Greyed out unless the last check found roles missing. Run Check Tenant again after a short wait for the change to replicate.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}

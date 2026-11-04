# Permissions

The Permissions page verifies that CIPP has the access it needs to manage your tenants. It runs three checks: one covering CIPP's own application registration, one covering your GDAP relationships, and one that tests access to each tenant individually. The results can be exported as a diagnostic report for troubleshooting or support. Where your tenants are added directly rather than through Microsoft Partner Center relationships, the GDAP check does not apply and access is confirmed per tenant by the Tenants check instead.

## Diagnostic Report

The buttons at the top of the page export the current check results, or load a report that was exported elsewhere. This is intended for troubleshooting and for sharing results with support.

| Action                | Description                                                                                                                                                                       |
| --------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Export Report         | Exports the current permissions, GDAP, and tenant results as a JSON file. A Redact Customer Data option is offered, which removes identifying tenant information from the export. |
| Import Report         | Loads a previously exported JSON report from a file so its results can be reviewed on this page.                                                                                  |
| Import from Clipboard | Loads a previously exported report directly from the clipboard rather than from a file.                                                                                           |
| Close report          | Clears the imported report and returns the page to live results.                                                                                                                  |

While an imported report is being viewed, each affected check is marked with an "Imported" label and its Refresh button is disabled, since the results come from the file rather than from your environment.

## Permissions Check

Checks the permissions granted to CIPP's application registration and reports anything missing. Select **Refresh** to run the check again without using cached results, or **Details** to open a flyout with the full breakdown. The time of the last run is shown beside the buttons.

The check also confirms that the secret CIPP authenticates with as its own application is still valid. CIPP renews that secret automatically ahead of its expiry date, so a problem is only reported where the stored secret has already expired, or is within a few weeks of expiring and has not been renewed. Both are reported on the card with the expiry date, and both need attention, because CIPP uses that secret to obtain access to your tenants.

Shortly after a renewal, the check can report that the secret CIPP is currently using does not match the one that is stored. That resolves itself once the new value is picked up, which takes up to thirty minutes. Where the secret cannot be checked at all, the card reports that rather than treating it as a failure.

{% hint style="info" %}
When this check flags missing permissions or required CPV refreshes, the Details flyout provides buttons to handle these tasks easily.
{% endhint %}

### Permissions not granted in your tenant

The check also compares the Microsoft Graph permissions CIPP needs with the ones actually granted to the CIPP-SAM application in your own tenant, once for application permissions and once for delegated permissions. Anything missing is reported as a warning rather than a failure, because CIPP keeps working, but the features that use those permissions fail. For example, certificate authentication needs the Application.ReadWrite.All application permission. The Details flyout lists each permission that is not granted.

CIPP grants these permissions itself during its nightly permission update, signed in as the CIPP service account. The usual cause is that the service account does not hold a role that is allowed to grant them. To fix it:

1. In Entra, assign the **Privileged Role Administrator** role to the CIPP service account. **Global Administrator** also works. If you use Privileged Identity Management, make the assignment active rather than eligible.
2. Wait for the next nightly permission update. A failed update is retried a day after the last attempt, so this can take up to two nights. To apply it straight away, run **Refresh CPV Permissions** on the \*Partner Tenant row under CIPP > Application Settings > Tenants. That row is listed only when the partner tenant is included in the tenant list, and the action needs a role with access to it.
3. Select **Refresh** on the Permissions check and confirm the warnings have cleared.

If you would rather not give the service account that role, a Global Administrator can grant the permissions manually:

1. Select the CIPP-SAM link next to **App Registration** on the Permissions check. It opens the application in the Azure portal.
2. Go to **API permissions**. Add any permission listed in the Details flyout that is not shown, choosing **Microsoft Graph** and then Application or Delegated permissions to match the Type column.
3. Select **Grant admin consent** for your tenant and confirm each permission shows as granted.
4. After a few minutes, select **Refresh** on the Permissions check. Newly granted permissions can take a short while to appear.

## GDAP Check

Checks your Granular Delegated Admin Privileges relationships and the roles they grant. As with the Permissions check, **Refresh** re-runs it and **Details** opens the full breakdown.

This check is only shown where it applies. In an environment whose tenants are added directly instead of through Partner Center relationships, the card is replaced with a note explaining that GDAP checks do not apply and that access is verified per tenant by the Tenants check below. The check also remains visible when an imported report contains GDAP results.

## Tenants Check

Tests access to each tenant in turn and reports what CIPP can reach. Select **Refresh** to re-run the check for every tenant.

### Table Details

| Column          | Description                                                                                                                                                                                              |
| --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant Name     | The name of the tenant.                                                                                                                                                                                  |
| Tenant Type     | How CIPP connects to the tenant: Direct for a tenant added with its own service account, or GDAP for one reached through a Partner Center relationship.                                                  |
| Service Account | For a direct tenant, the account CIPP authenticated as. Blank for GDAP tenants, which use the partner relationship rather than an account in the tenant.                                                 |
| Last Run        | When the access check last ran for this tenant.                                                                                                                                                          |
| Graph Status    | Whether CIPP could successfully reach Microsoft Graph in the tenant.                                                                                                                                     |
| Exchange Status | Whether CIPP could successfully reach Exchange Online in the tenant.                                                                                                                                     |
| Missing Roles   | Any required roles CIPP does not currently hold in the tenant.                                                                                                                                           |
| Assigned Roles  | The roles CIPP holds in the tenant. For a direct tenant these are the roles held by the service account; where that account is a Global Administrator, the roles it grants implicitly are noted as such. |

Selecting a row opens a flyout with further detail, including the tenant ID, default domain name, when the service account last authenticated, and the full results of the Graph and Exchange tests.

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Check Tenant</td><td>Re-runs the access check for the selected tenant.</td><td>true</td></tr><tr><td>Repair Exchange Roles</td><td>Restores the Exchange roles CIPP requires in the selected tenant. Available only where the check has found that a repair is needed.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}

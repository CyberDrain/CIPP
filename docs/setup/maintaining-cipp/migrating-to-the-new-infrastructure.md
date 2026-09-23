# Migrating Self Hosted to the New Infrastructure

This migration moves a self-hosted CIPP instance off the Function App and Static Web App architecture onto a single Linux container Web App. Your storage account and Key Vault are kept, so credentials and configuration carry across, and the old compute resources are removed as part of the cutover.

### Back up first

In CIPP, go to **Application Settings**, then select **Manage Backups** on the Backup card. Select **Run Backup** for a fresh backup, then use the **Download Backup** action on the row to save the file. It captures your instance configuration in case anything fails during the migration.

### Confirm prerequisites

* **PowerShell 7+** with the **Az** module, signed in to the Azure subscription that holds CIPP.
* **Owner** on the resource group, or **Contributor + User Access Administrator**. Owner is needed because the migration creates a role assignment, granting the new Web App's managed identity Contributor on itself, and that needs `roleAssignments/write`, which Contributor alone does not have. The script checks this up front and stops if it is missing.
* Download the files below, **both into the same folder**. The script loads its template from its own directory.
  * [`Invoke-CippMigration.ps1`](https://raw.githubusercontent.com/CyberDrain/CIPP/refs/heads/main/deployment/Invoke-CippMigration.ps1)
  * [`cipp-migration.json`](https://raw.githubusercontent.com/CyberDrain/CIPP/refs/heads/main/deployment/cipp-migration.json)

{% hint style="danger" %}
**A live run is destructive.** It **deletes** the existing Function Apps, App Service Plan, Application Insights components (and their smart-detector alert rules), and the Static Web App. It also **deletes every file share** in the storage account. The storage account itself and the Key Vault holding your credentials are preserved, along with the tables, blobs and queues CIPP's data lives in. Always run `-TestOnly` first, read the output, and only proceed once it looks right.
{% endhint %}

### Finish SSO migration

SSO must be at **`secrets_stored`** or **`complete`** before you cut over. You can find the SSO setup and its state under **CIPP → Advanced → Authentication → SSO**. If it is not set up yet, complete it there before going any further: see [sso.md](../../user-documentation/cipp/advanced/authentication/sso.md "mention").

{% hint style="warning" %}
A test run only **warns** about incomplete SSO, it does not stop. A clean-looking `-TestOnly` result is not confirmation that SSO is ready, so check the warnings in the output rather than the exit alone.
{% endhint %}

### Test run (`-TestOnly`)

From the folder where you saved both files, run:

```powershell
.\Invoke-CippMigration.ps1 -ResourceGroupName '<your-resource-group>' -TestOnly
```

Add `-CippUrl 'cipp.contoso.com'` if you use a custom domain, so the final summary includes the DNS records to create.

A test run changes nothing. It validates the template, detects the resources that would be affected, and confirms you have the permissions the migration needs.

If it reports that the resource group cannot be found even though it exists, the automatic subscription lookup has failed. Pass the subscription explicitly:

```powershell
$subId = (Get-AzContext).Subscription.Id
.\Invoke-CippMigration.ps1 -ResourceGroupName '<your-resource-group>' -SubscriptionId $subId -TestOnly
```

### Live run

If the test run looks right, run the same command without `-TestOnly`:

```powershell
.\Invoke-CippMigration.ps1 -ResourceGroupName '<your-resource-group>' -CippUrl 'cipp.contoso.com'
```

The new Web App is named after your existing Key Vault, because the backend resolves its Key Vault from the site name. Leave `-WebAppName` alone unless you have a reason to change it, and if you do set it, it has to match the Key Vault name.

If the instance has already been migrated, the script detects it and stops rather than running again. Passing `-Force` overrides that, and `-SkipIamCheck` skips the permission check, though a missing permission then surfaces partway through, after resources have been deleted.

### If the migration does not complete

Getting here should be rare, and a rebuild is the last resort rather than the expected response. Work through these in order.

**Run the script again.** A partial run usually leaves the instance in a state the script does not count as migrated, so the same command picks up where it left off. The already-migrated check only trips when a container web app exists, the resource group carries the `NG` tag, and no function apps remain, which a failed run rarely satisfies.

**If it stops and reports the migration as already complete, add `-Force`.**

```powershell
.\Invoke-CippMigration.ps1 -ResourceGroupName '<your-resource-group>' -CippUrl 'cipp.contoso.com' -Force
```

{% hint style="warning" %}
`-Force` past that check is not a redeployment. An instance the script has already detected as migrated has everything the template would create, so re-deploying is at best a no-op and can fail outright in a subscription with no spare VM quota. `-Force` therefore runs the remaining cleanup steps and skips the deployment. It clears leftovers after a run that mostly succeeded; it does not rebuild one that failed early.
{% endhint %}

**If re-running does not recover it, rebuild.** What survives is the important part: the script preserves the storage account and the Key Vault holding your credentials, so your configuration data and the four CIPP-SAM secrets are still there even when the compute resources have gone.

{% stepper %}
{% step %}
**Leave the old resource group alone.** The storage account and Key Vault in it are what the rebuild depends on.
{% endstep %}

{% step %}
**Deploy a fresh self-hosted instance into a new resource group.** Follow the self-hosted deployment on [install.md](../setting-up-cipp/install.md "mention"). Use a new resource group, because the deployment creates its own Key Vault and the name would collide with the one that survived.
{% endstep %}

{% step %}
**Point the new instance at your existing credentials.** Read the four secrets out of the old Key Vault and enter them in the new instance's Setup Wizard under "I have an existing application and would like to manually enter my tokens". Granting yourself access to the vault and reading the values works exactly as it does for a hosted migration: see [migrating-to-hosted-cipp.md](migrating-to-hosted-cipp.md "mention").
{% endstep %}

{% step %}
**Restore your backup.** In the new instance, go to **Application Settings**, then **Restore Backup**, and upload the file you downloaded before starting.
{% endstep %}

{% step %}
**Set up single sign-on and repoint your custom domain**, then verify the new instance before removing anything. The remaining sections on this page apply to it in the same way.
{% endstep %}
{% endstepper %}

{% hint style="warning" %}
Your logs do not come back with the restore. The `CippLogs` table stays in the old storage account, which a failed run leaves intact, so the history is still queryable there through a SAS URL from [siem.md](../../user-documentation/cipp/settings/siem.md "mention"). The new instance starts with an empty logbook.
{% endhint %}

{% hint style="info" %}
Support for a self-hosted instance is part of sponsorship. Raise a failed run with the helpdesk before rebuilding, in case the state you are in is recoverable.
{% endhint %}

### Repoint DNS

Point your custom-domain CNAME at the new Web App hostname the script printed, then add the domain in App Service. The script removes custom domains from the Static Web App before deleting it, but does **not** add them to the new App Service for you.

To add the domain in Azure:

1. **App Service → your CIPP app → Custom domains → Add custom domain**
2. Set **Domain provider** to **All other domain services**, **TLS/SSL certificate** to **App Service Managed Certificate**, **TLS/SSL type** to **SNI SSL**
3. Enter your hostname and complete validation, then confirm the managed certificate is issued and bound

### Add the redirect URI for the new hostname

The instance now answers on a different hostname from the Static Web App it replaced, and each hostname needs its own sign-in redirect URI of `https://<hostname>/.auth/login/aad/callback`. Any hostname without one fails sign-in with `AADSTS50011`, including the custom domain you have just added.

In CIPP, go to **CIPP** → **Advanced** → **Authentication** → **SSO** and select **Refresh Sign-in URLs**. It adds a redirect URI for every hostname currently bound to the instance and never removes an existing one, so it is safe to run again after any later domain change.

{% hint style="info" %}
The **Sign-in URLs** list on that page shows every hostname bound to the instance. One shown in orange is bound but has no matching redirect URI yet.
{% endhint %}

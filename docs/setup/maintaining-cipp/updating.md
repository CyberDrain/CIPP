---
description: >-
  Keeping CIPP up-to-date ensures you have the latest features, security
  patches, and bug fixes.
---

# Updating Versions

{% hint style="warning" %}
## **CyberDrain Hosted Clients**

If you’re using a CyberDrain-hosted instance of CIPP, updates happen automatically; generally, within **48 hours** of a new release. You can safely skip the rest of this page; however, it is important to perform a permissions check via CIPP > Application Settings > [permissions.md](../../user-documentation/cipp/settings/permissions.md "mention") to ensure any newly added permissions are accounted for.
{% endhint %}

Update your self-hosted CIPP instance to the latest release using the following instructions:

{% stepper %}
{% step %}
### Log in to CIPP

Log in to CIPP as a superadmin account
{% endstep %}

{% step %}
### Open Container Management

Go to CIPP -> Advanced -> Container Management -> [status.md](../../user-documentation/cipp/advanced/container-management/status.md "mention")
{% endstep %}

{% step %}
### Update Management

Set your auto-update settings or press the "Check now" button to check for updates and install them.

{% hint style="info" %}
You can optionally change which Release Channel you target for updates. Use caution when running Dev or Nightly as these can contain untested changes.
{% endhint %}
{% endstep %}
{% endstepper %}

## Legacy Self-Hosted (Static Web App + Function App)

Instances still running the earlier Function App and Static Web App architecture, from before the [migrating-to-the-new-infrastructure.md](migrating-to-the-new-infrastructure.md "mention") migration, have no Container Management page and update by syncing their GitHub fork instead.

{% stepper %}
{% step %}
### Sync your CIPP fork

Open your fork of the CIPP repository on GitHub, click Sync Fork, then Update Branch.

{% hint style="danger" %}
If GitHub asks whether to discard commits or update the branch, choose Update Branch. Discarding commits removes your fork's deployment workflow file.
{% endhint %}
{% endstep %}

{% step %}
### Repeat for your CIPP-API fork

Sync this fork the same way, so the frontend and API stay on matching versions.
{% endstep %}

{% step %}
### Wait for deployment

If your Function App is connected to GitHub Actions for continuous deployment, the update rolls out on its own, typically within around 30 minutes. Check the Actions tab on each repository, or the Azure logs, to confirm it succeeded.
{% endstep %}

{% step %}
### Clear your browser cache

If you still see the previous version, do a hard refresh: open the browser's developer tools, then right-click the refresh button and select the option to empty the cache and reload.
{% endstep %}

{% step %}
### Run a permissions check

Go to CIPP > Application Settings > [permissions.md](../../user-documentation/cipp/settings/permissions.md "mention") and repair any permissions the update added.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
Syncing both forks manually on every release is easy to forget. The [Pull GitHub App](https://github.com/apps/pull) can open the sync as a pull request for you automatically, which you then only need to review and merge.
{% endhint %}

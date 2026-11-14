---
description: Investigate an app or managed identity for compromise, and contain it.
---

# NHI Case

This page investigates a single app (enterprise application) or managed identity for compromise. A run looks at the last 7 days against the 23 days before them: where the app signed in from and with which credential, every change made to it, what it changed in the directory, the mail and files it reached, and the users signing in to it. Each run is kept as a case. A completed case opens with a triage header (the case level, the signals behind it and the actions), followed by the findings, then the containment history.

{% hint style="warning" %}
Nothing on this page is proof of a compromise. The checks surface what usually matters during an investigation, and several of them return results for perfectly healthy apps. Read the findings alongside what you already know about the app and what it is used for.
{% endhint %}

## Running the Investigation

Nothing runs when the page opens. It loads the app's runs and shows the latest one, or a status card with **Start investigation** when the app has none. Arriving from **Start investigation** on the [NHI Compromise](README.md) page, from **Investigate compromise** on an enterprise application or from the [App Permission Exposure](../../reports/app-permission-exposure.md) report starts a run straight away.

Starting a run queues a background job, and the status card shows whether it is **Queued** or **Running**, with each step and its outcome as it completes. A run that makes no progress for six hours, typically because the background worker restarted, is marked **Failed** with the reason shown, and the button becomes **Run again**. The failed run stays in the app's history.

A step that fails, or stops before it finishes, does not end the run: the remaining steps still run, and the completed case lists the affected checks in a warning above the findings. Only a failure in the first step, which reads the app itself, or in the last, which judges the addresses and scores the case, marks the whole run **Failed**.

When the app has more than one run, a **Case** switcher at the top of the page lists them, each with its date, case level and case ID. Pick one to view it exactly as it was collected. **← All NHI cases** goes back to the [NHI Compromise](README.md) page, which lists every case for every app and tenant and is where runs are deleted.

Everything collected is metadata: sign-ins, credentials, owners, permissions, directory audits and unified audit log records. No message body or file content is read or stored.

## Triage Header

The header of a completed case shows how serious it looks, why, and what to do about it.

| Part       | What it shows                                                                                                                                                                                                                                                                                                                                       |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Case level | The case level (Critical, High, Medium or Low), with the evidence level, the evidence score and the impact of the app's access that produced it. When the app's access could not be rated, the impact is marked unknown.                                                                                                                           |
| App        | The app's name, whether it is a managed identity or who owns it, its application ID, its verified publisher where it has one, and whether it is disabled. A managed identity also shows its Azure resource. **Open the enterprise app** opens the app in CIPP.                                                                                        |
| Sign-ins   | How many sign-ins the app made in the window and from how many networks, against how many in the days before, and how many addresses were judged to be an attacker's.                                                                                                                                                                              |
| Why        | Every scoring signal that fired, with the points it added and how many results it counted, or **No compromise signal fired**. Below it, the exposure of the app's access: its risk, its highest impact and how many risky permissions it holds.                                                                                                     |

### Case Level

The case level crosses two ratings. The **evidence level** says how sure the run is that the app is compromised: every signal that fires adds its points once, and a total of 7 or more is High, 4 to 6 Medium and anything lower Low. The **impact** is the highest impact of the app's access, the same rating the [App Permission Exposure](../../reports/app-permission-exposure.md) report gives it. Strong evidence against an app that can read one mailbox is a Medium case, while moderate evidence against an app holding Global Administrator is a High one.

| Evidence level | Low impact | Medium impact | High impact | Critical impact |
| -------------- | ---------- | ------------- | ----------- | --------------- |
| Low            | Low        | Low           | Low         | Medium          |
| Medium         | Low        | Medium        | Medium      | High            |
| High           | Medium     | High          | Critical    | Critical        |

When the app's access could not be rated, its impact counts as Medium, never as harmless. A signal that was found but not counted says why in **Why**, for example mail and file activity from an address judged to be an attacker's on network evidence alone, or access granted by CIPP's own app as part of managing the tenant.

### Actions

| Action                | Description                                                                                                                                                                                       |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Contain app           | Opens the containment drawer described under [#containment](case.md#containment "mention"). Greyed out without the `Tenant.Application.ReadWrite` permission.                                     |
| Run new investigation | Starts a new run. The earlier case stays in the **Case** switcher. The page shows the run's progress while it completes.                                                                          |
| Download evidence     | Builds the evidence package for the case on screen and downloads it. If an export fails, the reason is shown below the buttons. See [#evidence-export](case.md#evidence-export "mention").         |

### Checks Not Run

Above the findings, an information banner lists the checks that were **Not checked**, with what each one needs: for example Microsoft Entra ID P1 for sign-in logs, or Microsoft Entra Workload ID Premium for Identity Protection. A warning lists the checks that failed or reached a cap. Treat an empty section that one of these affects as unconfirmed, not clean.

## Findings

Each set of findings is a collapsible section showing how many results it holds. A section with flagged results opens on its own and shows how many are flagged.

| Section                               | What it shows                                                                                                                                                                                                                                                                                                                            |
| ------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Addresses                             | Every address the app signed in or acted from, judged against where it signed in from before the window. Each has a verdict, a score and the reasons behind it with the points each added or took away, its sign-in and activity counts, country and network, and the credentials and resources used from it.                             |
| Credentials                           | Every secret, certificate and federated credential on the enterprise app and app registration, with when and by whom it was added, its validity, and when it last signed in. A credential is flagged when it was added in the window, added by another app, backdated, or trusts an identity provider CIPP does not recognise. Beneath it, **Sign-ins by credential** shows how often each credential signed in, and from where. |
| Changes to the app                    | Every change to the enterprise app and app registration since the baseline began, who or what made it, and whether it fell in the window.                                                                                                                                                                                               |
| Elevation                             | Permissions and directory roles the app gave itself, other apps or users, rated by what they allow. That access stays after the app is disabled.                                                                                                                                                                                       |
| App persistence                       | Apps the app created, and credentials or owners it added to other apps. Each can keep access after the app is disabled.                                                                                                                                                                                                                |
| This app in your other tenants        | The same app in the other tenants you manage. A compromised app usually reaches every tenant it is consented in.                                                                                                                                                                                                                       |
| What the app changed in the directory | Other directory changes the app made, with their severity and targets.                                                                                                                                                                                                                                                                 |
| Mail and files the app reached        | A summary of the mailboxes, mail items, messages sent, anonymous links, files, sites and inbox rule changes the app touched, from the unified audit log, with the mailboxes and sites it reached before the window. Only reach beyond what it touched before counts as mass access. Tables list the mailboxes, sites and inbox rules.            |
| Users signing in to the app           | The users who signed in to the app, with their sign-in counts, addresses and countries, and any consents given to it.                                                                                                                                                                                                                   |
| Access and owners                     | What a compromise of the app reaches and who can add a credential to it: the reasons behind its exposure rating, its application permissions, delegated consents, directory roles, and the owners of the enterprise app and app registration.                                                                                          |
| Recent sign-ins                       | The app's most recent individual sign-ins, with the address and its verdict, the outcome, the resource, the credential used and the network.                                                                                                                                                                                            |

### Following the Trail

Three sections can start an investigation of something the app touched, each opening a new case and starting its run:

* **Elevation**: **Investigate this app** for access granted to another app, and **Investigate this user (BEC)** for access granted to a user, which opens the [Compromise Remediation](../../../identity/administration/bec/case.md) page for that user.
* **App persistence**: **Investigate this app** for each app it created or added a credential or owner to.
* **This app in your other tenants**: **Investigate in this tenant** for each other tenant the app is in.

Each is greyed out where the row has nothing to investigate, for example an elevation whose recipient is the app itself.

## Containment

**Contain app** opens a drawer listing every containment action, grouped by impact from Critical to Low. Each action is a switch with a description beneath it, and actions that cannot be undone are marked **(not reversible)**. Switching on an action that takes targets shows a **Targets** picker filled from the case, with the flagged items already selected. Where the case found nothing of that kind, the drawer says so and nothing is changed. Nothing the app may depend on is removed unless it is selected.

| Action                                            | Impact   | What it does                                                                                                                                                                                                                       |
| ------------------------------------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Disable the app in this tenant                    | Critical | Stops the app getting new tokens, for every user and every credential. Tokens already issued stay valid until they expire, about an hour. Reversible. On by default, except for a managed identity.                                |
| Remove flagged credentials                        | Critical | Deletes the selected secrets and certificates from the enterprise app and app registration. By default, the flagged ones. On by default.                                                                                           |
| Remove federated credentials                      | High     | Deletes the selected federated credentials from the app registration. By default, those trusting an identity provider CIPP does not recognise or another Entra tenant.                                                             |
| Remove owners                                     | High     | Removes the selected owners of the enterprise app and app registration. Every owner can add a credential and act with the app's access.                                                                                            |
| Revoke application permissions                    | Critical | Removes the selected application permissions. By default, those granted in the window.                                                                                                                                             |
| Revoke delegated consents                         | High     | Removes the selected delegated consents, so the app loses the access users or an administrator consented to.                                                                                                                       |
| Remove directory roles                            | Critical | Removes the selected directory roles held directly by the app.                                                                                                                                                                     |
| Confirm compromised in Identity Protection        | High     | Marks the app confirmed compromised, so risk-based Conditional Access for workload identities blocks it. Needs Microsoft Entra Workload ID Premium.                                                                                 |
| Lock app instance properties                      | Medium   | For an app registered in this tenant, stops any organisation it is consented in adding a credential to its copy of the app. Reversible.                                                                                           |
| Disable the apps it created or put credentials on | Critical | Disables the apps this app created, or added a credential or owner to. By default, those of the window. Microsoft's and CIPP's own apps are never disabled. Reversible.                                                            |
| Revoke the access it granted                      | Critical | Removes the permissions and directory roles the app gave itself, other apps or users. By default, the high-impact ones of the window. For delegated consents, only the scopes the app added are removed.                           |

Disabling the app stops new tokens but not the ones it already holds, so remove its credentials as well. A managed identity cannot be disabled here: Azure manages its credentials, and the drawer says to remove it from its Azure resource instead. Its permissions and roles can still be removed.

When a Critical action is switched on, the drawer lists the Critical actions selected and asks you to type the app's display name, or its application ID, in **Type the app's display name to confirm**. **Run containment** is greyed out until something is selected and, for Critical actions, the name matches. Each action runs separately, so one failure does not stop the rest, and the drawer shows a result for each action and target.

Containment can only be run from a completed case.

### Containment History

Once containment has run, a **Containment history** section at the foot of the case lists every result row: when, by whom, whether it was containment or a release, the action, its outcome and the target.

### Releasing the App

At the foot of **Containment history**, type the app's display name in **Type the app's display name to release** and select **Release: re-enable the app**. This re-enables what the case disabled and is still in force: the app itself, and the apps it created or put credentials on. Use it once the app is clean or its credentials have been replaced.

Removed credentials, owners, permissions, consents and roles are not restored. The release lists each one as something to re-create by hand if it is still needed. The app instance property lock stays on. The release is recorded in the containment history, and the button needs the `Tenant.Application.ReadWrite` permission.

## Evidence Export

**Download evidence** builds a ZIP of the case: the full results, one CSV per set of findings, the score, the containment history, and every logbook entry stamped with the case ID. The package is built fresh for every export and nothing is kept on the server afterwards. **Download evidence (ZIP)** on the [NHI Compromise](README.md) page produces the same package. Only a completed case can be exported, and the list of the app in your other tenants is left out.

{% include "../../../../../.gitbook/includes/feature-request.md" %}

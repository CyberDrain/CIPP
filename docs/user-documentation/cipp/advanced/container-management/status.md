# Status & Updates

The Status & Updates page lets you view and manage the CIPP application container, on both self-hosted and CyberDrain-hosted instances. From here you can see which image and version are running, control the release channel, configure automatic update checks, and restart the container.

The page is laid out top to bottom: a status strip summarising the running container, any notices that need action, a row of action buttons, and two settings cards.

## Status Strip

The strip across the top of the page summarises the state of the running container in four tiles.

| Tile            | Description                                                                                                                                                      |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Release Channel | The channel the running container was built from. Hover to see the running image tag. A branch build shows its own tag here, in red, rather than a channel name. |
| App Version     | The version of CIPP currently running, followed by the short commit it was built from. Select the tile to open **Build Details**.                                |
| Update Status   | **Never checked**, **Update available**, **Up to date**, **Update unverified**, **Up to date, unverified**, or **Running image unverified**. The unverified states are explained under [#provenance](status.md#provenance "mention"). Select the tile to open **Latest on this channel**. |
| Last Checked    | How long ago the last update check ran, such as `3h ago`. Hover for the exact date and time, in your local time zone.                                            |

Selecting the App Version tile opens a **Build Details** panel:

| Field             | Description                                                        |
| ----------------- | ------------------------------------------------------------------ |
| Image Tag         | The tag of the running container image.                            |
| Commit SHA        | The source commit the running image was built from.                |
| Image Built (UTC) | The date and time the running image was built.                     |
| Container Image   | The full reference of the running container image, when known.     |
| App Service       | The name of the App Service hosting the container, when available. |
| Pinned Digest     | The image digest the instance is pinned to, when it is pinned. Hover to see the full digest. |
| Provenance        | Whether the image the instance is running passed provenance verification. |

Selecting the Update Status tile opens a **Latest on this channel** panel, showing the version, build date, image digest and provenance result of the newest image found on your channel by the last check.

Build details are baked into the image when it is built, and some of them are simply absent from locally built and development images. Any field the running build does not report is left out of these panels rather than shown as unknown, so a development image may show only two or three rows.

## Notices

Notices can appear directly below the status strip, and only when there is something to act on.

* A **channel change is pending**: the running and configured channels differ, and the container needs to be restarted to apply the change. Both channels are named in the notice.
* A **container update is available**: a newer image has been published on your channel, and restarting will pull it.
* The **latest image on your channel did not pass provenance verification**: shown in place of the update notice. It says whether a restart keeps the pinned image or pulls the unverified image anyway.

## Actions

Three buttons sit between the status strip and the settings cards.

| Action            | Description                                                                                                                    |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Refresh Status    | Re-reads the status of the running container. This does not contact the container registry, so it can never trigger a restart. |
| Check for Updates | Asks the container registry whether a newer image has been published on your channel. Opens a confirmation dialog first.       |
| Restart Container | Restarts the application container. Opens a confirmation dialog first.                                                         |

### Check for Updates

{% hint style="warning" %}
A manual update check is not always read-only. If **Auto-restart when an update is detected** is enabled, finding a newer image restarts the container immediately, causing brief downtime. The dialog warns you when this is the case and its button reads **Check & Apply** instead of **Check Now**. Use **Refresh Status** if you only want to re-read the current state.
{% endhint %}

With auto-restart off, a check only records what it found. Nothing is pulled and nothing restarts until you restart the container yourself.

### Restart Container

Restarting causes a brief period of downtime while the container comes back up. What it comes back on depends on whether the instance is pinned to an image digest:

* **Pinned**: it comes back on the pinned image, moved to the newest image on the channel only if that image passed provenance verification.
* **Not pinned**: the newest image on the current channel is pulled as it comes back, so a restart updates to the latest image on the channel whatever the reason for the restart, including a channel change or a pending update.

The confirmation dialog says which applies, and warns you when an unpinned restart would pull an image that failed verification.

## Release Channel

This card selects which release channel the container follows. Changing the channel updates the container image tag; the new image is pulled on the next container restart.

| Channel         | Description                                                         |
| --------------- | ------------------------------------------------------------------- |
| Latest (Stable) | The stable release channel.                                         |
| Dev             | Development builds, which may include unstable or untested changes. |
| Nightly         | Nightly builds, which may include unstable or untested changes.     |

Choose a channel and select **Update Channel** to apply it. The change takes effect on the next container restart. Switching to Dev or Nightly may introduce unstable or untested changes.

The channel list is read from the container registry when the page loads, grouped into **Standard channels** and any branch builds that currently exist. Use the refresh button on the field to reload the list without reloading the page, which is useful when waiting for a branch build to finish. The field also accepts a tag typed by hand as a fallback; whatever you enter is validated before it is saved.

### Branch builds

Below the standard channels the list may also show **Branch builds**: images built from a branch that has not been merged yet, so a change can be tested on a real instance before it ships. They are named after the branch they came from, such as `fix-sso-multi-domain` or `feat-new-report`.

A branch build tag follows its branch, in the same way `dev` and `nightly` do: if the branch is built again, the container picks up the newer image on its next restart. To hold one exact build instead, set the container image to its digest rather than its tag. The build summary in the GitHub Actions run prints the full reference to use.

Only builds that currently exist are listed, and the tag is checked before the change is saved, so a build that has already been removed cannot be selected by mistake.

Branch builds are **not supported** and are intended for testing only:

* They receive no updates, and the automatic update check does not apply to them.
* They are deleted when their branch is deleted, and swept after 30 days. Once the image is gone the container cannot start until you switch back to a standard channel, so move off a branch build as soon as you have finished testing.

Selecting a branch build shows a warning in the card before you save it, and the Release Channel tile turns red once one is running.

Unless you have been asked to test a specific build, stay on Latest (Stable).

## Update Checks

This card configures how often CIPP asks the container registry whether a newer image has been published on your channel. By default, it checks every hour and auto-restarts at 23:00.

| Setting                                 | Description                                                                                                                                  |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Check Interval                          | How often CIPP checks the registry for a new image: Disabled, Every hour, Every 4 hours, Every 12 hours, or Every day.                       |
| Preferred Restart Time                  | The hour of the day, in 24-hour time, at which the check runs and, with auto-restart on, the container restarts to apply an update it finds. |
| Auto-restart when an update is detected | When enabled, CIPP automatically restarts the container to apply an update once one is found.                                                |

Select **Save Settings** to store these options. Setting Check Interval to **Disabled** turns off scheduled checks and disables the other two settings, as neither has any effect without them; you can still check on demand with **Check for Updates**.

### Provenance

Every check also verifies the newest image on your channel: its signed build attestation is fetched from the registry and checked against the release workflow of the repository the image came from. The **Latest on this channel** panel shows the result whether or not an update is pending, and an update is only applied automatically when it passes:

| Result       | Meaning                                                                                                                                              |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Verified     | The image was built and signed by the expected CI workflow. Auto-restart proceeds as configured.                                                      |
| Failed       | No attestation was found, or it did not match. With an update pending, auto-restart is withheld, a warning is logged and the restart dialog warns you; when already up to date the result is simply shown.  |
| Unverifiable | The attestation could not be checked, for example a registry error or a private fork signed by a certificate authority CIPP does not carry. The check retries next interval. |

Verified says who built the image, not who reviewed it. On the **dev** and **nightly** channels it shows as **Verified · Dev**: those images are built from the dev branch, which accepts direct pushes before release review. Branch builds show **Verified · Preview**. Only **latest** is built from a release tag on main, where pull requests are required, and shows plain **Verified**. The Release Channel card shows a warning when a dev or nightly channel is selected.

See [verifying-container-images.md](../../../../security/cipp-security-and-compliance/verifying-container-images.md "mention") for how to verify an image yourself and what to do when building from a fork.

When an update passes verification and is applied, the instance is pinned to that image's digest, so a later restart cannot pick up a different image under the same tag. With auto-restart on, an instance that is not yet pinned is pinned to its verified channel image once, which restarts it onto the same image. An image that fails or cannot be verified never moves the pin. Until an instance is pinned, a restart for any reason pulls the latest image for the current release channel regardless of these settings.

The **Provenance** row under **Build Details** checks the image the instance is actually running. If the running image fails that check, the Update Status tile shows **Running image unverified**.

## Update History

The version changes recorded for this instance, newest first, so you can see when it landed on the build it is running and what it was on before.

| Column           | Description                                                     |
| ---------------- | --------------------------------------------------------------- |
| Recorded At      | How long ago the change was recorded, such as `3 hours ago`.    |
| Previous Version | The version the instance was running before the change.         |
| New Version      | The version it moved to.                                        |
| Image Tag        | The image tag it landed on.                                     |

A change is recorded when the container starts on a different version from the one last seen, so the time recorded is when the new build first ran rather than when the image was published. The most recent 50 changes are shown.

Until a change has been recorded the table is empty. Version transitions are recorded from the next update onward, so a newly deployed instance starts with an empty history rather than a backfilled one.

{% include "../../../../../.gitbook/includes/feature-request.md" %}

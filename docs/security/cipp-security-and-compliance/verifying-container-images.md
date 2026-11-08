# Verifying Container Images

## Build Provenance

Every `latest`, `dev`, and `nightly` CIPP image carries a signed build-provenance attestation, created by the CyberDrain/CIPP build workflows when the image is pushed. The attestation ties the image digest to the exact workflow run and commit that produced it.

## Verifying an Image

With the [GitHub CLI](https://cli.github.com/) installed, run:

```
gh attestation verify oci://ghcr.io/cyberdrain/cipp:latest --owner CyberDrain
```

Use `:dev` or `:nightly` in place of `:latest` to check those channels.

A successful result confirms the signature and shows the source repository (CyberDrain/CIPP), the workflow that built the image, and the commit it was built from.

## Images Without an Attestation

An image without a valid attestation did not come from CI and should not be run. If verification fails for an image you pulled from `ghcr.io/cyberdrain/cipp`, report it to [security@cyberdrain.com](mailto:security@cyberdrain.com).

## How CIPP Uses the Attestation

On every update check, CIPP fetches the attestation for the newest image on your channel and verifies it: the signature, the certificate chain, and that the signer is the release workflow of the repository the image came from. The result is shown as **Provenance** on CIPP > Advanced > Container Management > [status.md](../../user-documentation/cipp/advanced/container-management/status.md "mention"). An image that fails verification is never applied automatically; you can still restart by hand, and the restart dialog warns you first.

Nothing needs to be configured. The check uses the same anonymous registry access as the update check itself.

## Building Your Own Image

If you build CIPP from a fork and run that image, CIPP expects the attestation to come from **your** repository's build workflow, because the image path on the registry names your fork. The attestation step is part of the container workflows in this repository, so a fork that has synced `dev` or `main` since the step was added already has it. Check that your fork's `.github/workflows/*-container.yml` files still contain the `Attest build provenance` step and the `id-token` and `attestations` permissions.

Two cases do not verify:

* **Private forks.** GitHub signs attestations for private repositories with its own certificate authority, which CIPP does not carry. The result shows as **Unverifiable** and the automatic restart is withheld; manual restarts still work.
* **Images pushed by hand** with `docker push` carry no attestation at all. They show as **Failed** and are never applied automatically.

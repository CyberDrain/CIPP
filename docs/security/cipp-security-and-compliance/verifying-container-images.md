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

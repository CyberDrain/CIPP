import { useEffect, useState } from "react";
import { Alert, Button, Chip, Link, Stack, TextField, Typography } from "@mui/material";
import { Grid } from "@mui/system";
import CippButtonCard from "../CippCards/CippButtonCard";
import { ApiGetCall, ApiPostCall } from "../../api/ApiCall";
import { CippApiResults } from "../CippComponents/CippApiResults";
import { CippCopyToClipBoard } from "../CippComponents/CippCopyToClipboard";

export const GOV_APP_DOCS_URL =
  "https://docs.cipp.app/setup/installation/government-direct-tenants#permissions";

const GUID_PATTERN = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;

const formatDate = (value) => (value ? new Date(value).toLocaleDateString() : "—");

// PEM wrapper around the base64 DER the backend returns - the public part only.
export const toPem = (base64) =>
  `-----BEGIN CERTIFICATE-----\n${base64.match(/.{1,64}/g).join("\n")}\n-----END CERTIFICATE-----\n`;

const downloadCertificate = (base64) => {
  const blob = new Blob([toPem(base64)], { type: "application/x-pem-file" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "cipp-gov-app.cer";
  link.click();
  URL.revokeObjectURL(url);
};

const Row = ({ label, children }) => (
  <>
    <Grid size={{ xs: 12, sm: 4 }}>
      <Typography variant="body2" sx={{ color: "text.secondary" }}>
        {label}
      </Typography>
    </Grid>
    <Grid size={{ xs: 12, sm: 8 }}>{children}</Grid>
  </>
);

// Azure Government app registration used to sign in to direct GCC High and DoD tenants
// (redanthrax/CIPP#2). The secret is write-only: the backend never returns it.
export const CippGovAppCredentials = () => {
  const status = ApiGetCall({
    url: "/api/ExecGovAppCredentials",
    data: { Action: "Status" },
    queryKey: "GovAppCredentialsStatus",
  });
  const save = ApiPostCall({ relatedQueryKeys: ["GovAppCredentialsStatus", "listAppId"] });
  const generate = ApiPostCall({ relatedQueryKeys: ["GovAppCredentialsStatus"] });

  const data = status.data?.Results;
  const certificate = data?.certificate ?? {};
  const [applicationId, setApplicationId] = useState("");
  const [applicationSecret, setApplicationSecret] = useState("");

  // The sign-in button sends `${window.location.origin}/authredirect` (CIPPM365OAuthButton), so that
  // is the value to register - the backend cannot always see the browser's scheme and port.
  const [redirectUri, setRedirectUri] = useState(null);
  useEffect(() => {
    if (typeof window !== "undefined") setRedirectUri(`${window.location.origin}/authredirect`);
  }, []);

  useEffect(() => {
    if (data?.applicationId) setApplicationId(data.applicationId);
  }, [data?.applicationId]);

  useEffect(() => {
    // Drop the typed secret once it has been stored.
    if (save.isSuccess) setApplicationSecret("");
  }, [save.isSuccess]);

  const idValid = GUID_PATTERN.test(applicationId.trim());
  // An id typed but not saved yet. Generating a certificate does not save it.
  const idUnsaved = applicationId.trim() !== "" && applicationId.trim() !== (data?.applicationId ?? "");
  const certificateAuthMode = data?.certificateAuthMode === true;
  const usesCertificate = data?.credentialInUse === "certificate";
  const credentialInUseText = !data
    ? "—"
    : usesCertificate
      ? certificateAuthMode
        ? "Certificate (this instance uses certificate authentication)"
        : "Certificate (no client secret stored)"
      : "Client secret";
  const generatedCertificate = generate.data?.data?.Results?.publicCertificate;
  const publicCertificate = generatedCertificate ?? certificate.publicCertificate;

  return (
    <CippButtonCard
      title="Azure Government app (GCC High / DoD)"
      isFetching={status.isFetching}
      cardActions={
        <Chip
          size="small"
          variant="outlined"
          label={data?.configured ? "Configured" : "Not configured"}
          color={data?.configured ? "success" : "default"}
        />
      }
    >
      <Grid container spacing={1}>
        <Grid size={12}>
          <Typography variant="body2" sx={{ mb: 1 }}>
            Direct tenants in GCC High or DoD sign in through an app registered in Azure Government
            (portal.azure.us), not CIPP-SAM. Register a multi-tenant app there, add the redirect URI
            below as a Web redirect URI, give it the same Microsoft Graph permissions as CIPP-SAM
            (delegated and application, matched by name: some ids differ in Azure Government) and
            grant admin consent, then enter its application ID and save it. Add the certificate
            generated here to the app registration, or a client secret if this instance does not use
            certificate authentication.{" "}
            <Link href={GOV_APP_DOCS_URL} target="_blank" rel="noopener noreferrer">
              Permissions and setup guide
            </Link>
          </Typography>
        </Grid>
        <Row label="Authority">
          <Typography variant="body2">{data?.authority ?? "—"}</Typography>
        </Row>
        <Row label="Redirect URI">
          {redirectUri ? <CippCopyToClipBoard text={redirectUri} type="chip" /> : "—"}
        </Row>
        <Row label="Signs in with">
          <Typography variant="body2">{credentialInUseText}</Typography>
        </Row>
        <Row label="Client secret">
          <Typography variant="body2">{data?.hasSecret ? "Stored" : "None"}</Typography>
        </Row>
        <Row label="Certificate">
          <Typography variant="body2">
            {certificate.configured
              ? certificate.error ?? `${certificate.thumbprint} (expires ${formatDate(certificate.notAfter)})`
              : "None"}
          </Typography>
        </Row>

        <Grid size={12} sx={{ mt: 2 }}>
          <Stack spacing={2}>
            <TextField
              label="Application (client) ID"
              size="small"
              value={applicationId}
              onChange={(event) => setApplicationId(event.target.value)}
              error={applicationId !== "" && !idValid}
              helperText={applicationId !== "" && !idValid ? "Enter the app's GUID" : " "}
            />
            <TextField
              label={data?.hasSecret ? "New client secret (leave empty to keep the stored one)" : "Client secret"}
              size="small"
              type="password"
              autoComplete="new-password"
              value={applicationSecret}
              onChange={(event) => setApplicationSecret(event.target.value)}
              disabled={certificateAuthMode}
              helperText={
                certificateAuthMode
                  ? "Not used: this instance uses certificate authentication, so the Azure Government app signs in with its certificate."
                  : " "
              }
            />
            {idUnsaved && idValid && (
              <Alert severity="warning">
                This application ID has not been saved yet. Select Save to store it; generating a
                certificate does not save it.
              </Alert>
            )}
            <Stack direction="row" spacing={1} useFlexGap sx={{ flexWrap: "wrap" }}>
              <Button
                variant="contained"
                disabled={!idValid || save.isPending}
                onClick={() =>
                  save.mutate({
                    url: "/api/ExecGovAppCredentials",
                    data: {
                      Action: "Save",
                      applicationId: applicationId.trim(),
                      ...(applicationSecret ? { applicationSecret } : {}),
                    },
                  })
                }
              >
                Save
              </Button>
              <Button
                variant="outlined"
                disabled={generate.isPending}
                onClick={() =>
                  generate.mutate({
                    url: "/api/ExecGovAppCredentials",
                    data: { Action: "GenerateCertificate" },
                  })
                }
              >
                {certificate.configured ? "Generate new certificate" : "Generate certificate"}
              </Button>
              {publicCertificate && (
                <Button variant="outlined" onClick={() => downloadCertificate(publicCertificate)}>
                  Download certificate
                </Button>
              )}
            </Stack>
            {usesCertificate && !certificate.configured && (
              <Alert severity="warning">
                The Azure Government app signs in with a certificate, but none is stored. Generate one
                and upload it to the app registration.
              </Alert>
            )}
            {certificate.configured && usesCertificate && (
              <Alert severity="info">
                Generating a new certificate replaces the stored one immediately. Upload it to the app
                registration before signing in again.
              </Alert>
            )}
            <CippApiResults apiObject={save} />
            <CippApiResults apiObject={generate} />
          </Stack>
        </Grid>
      </Grid>
    </CippButtonCard>
  );
};

export default CippGovAppCredentials;

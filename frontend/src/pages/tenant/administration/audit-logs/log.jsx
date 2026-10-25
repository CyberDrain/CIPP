import { useRouter } from "next/router";
import { CippIcons } from "../../../../utils/icon-registry";
import { useEffect, useState } from "react";
import { Layout as DashboardLayout } from "../../../../layouts/index";
import { ApiGetCall } from "../../../../api/ApiCall";
import {
  Box,
  Typography,
  Paper,
  CardHeader,
  Card,
  CardContent,
  Button,
  Chip,
  Divider,
  Stack,
  SvgIcon,
  Tooltip,
} from "@mui/material";
import CippFormSkeleton from "../../../../components/CippFormPages/CippFormSkeleton";
import { getCippFormatting } from "../../../../utils/get-cipp-formatting";
import { getCippTranslation } from "../../../../utils/get-cipp-translation";
import CippGeoLocation from "../../../../components/CippComponents/CippGeoLocation";
import { CippTimeAgo } from "../../../../components/CippComponents/CippTimeAgo";
import { CippDataTable } from "../../../../components/CippTable/CippDataTable";
import { Grid } from "@mui/system";
import auditLogTranslation from "../../../../data/audit-log-translations.json";
import { ArrowLeftIcon } from "@mui/x-date-pickers";
import { CippAuditLogRuleCheck } from "../../../../components/CippComponents/CippAuditLogRuleCheck";

// Fields shown elsewhere on the page, or only useful to CIPP itself.
const excludeProperties = [
  "CreationTime",
  "CIPPLocationInfo",
  "CIPPParameters",
  "CIPPModifiedProperties",
  "CIPPAction",
  "CIPPCondition",
  "CIPPIPDetected",
  "CIPPExtendedProperties",
  "CIPPDeviceProperties",
  "CIPPGeoLocation",
  "CIPPClause",
  "AuditRecord",
];

// Audit times are UTC without a zone marker.
const parseAuditTime = (value) =>
  value ? new Date(/[zZ]|[+-]\d\d:\d\d$/.test(value) ? value : `${value}Z`) : null;

const SummaryRow = ({ icon, label, children }) => (
  <Stack direction="row" spacing={2} sx={{ alignItems: "flex-start" }}>
    <Box sx={{ color: "text.secondary", display: "flex", mt: 0.25 }}>{icon}</Box>
    <Box sx={{ minWidth: 0 }}>
      <Typography variant="caption" sx={{ color: "text.secondary" }}>
        {label}
      </Typography>
      <Typography variant="body2" component="div" sx={{ wordBreak: "break-word" }}>
        {children}
      </Typography>
    </Box>
  </Stack>
);

const Page = () => {
  const router = useRouter();
  const { id } = router.query;
  const [logData, setLogData] = useState(null);
  const [lookupIp, setLookupIp] = useState(null);

  const logRequest = ApiGetCall({
    url: `/api/ListAuditLogs`,
    data: {
      logId: id,
    },
    queryKey: `GetAuditLog-${id}`,
  });

  const translateAuditLogValue = (key, value) => {
    if (typeof value === "object" || Array.isArray(value)) {
      return value;
    }
    if (typeof value === "boolean") {
      return value;
    }
    if (
      typeof value === "string" &&
      (value.toLowerCase() === "true" || value.toLowerCase() === "false")
    ) {
      return value.toLowerCase() === "true";
    }
    const stringValue = String(value);
    if (auditLogTranslation[key]) {
      return auditLogTranslation[key][stringValue] ?? stringValue;
    }
    return stringValue;
  };

  useEffect(() => {
    if (logRequest.isSuccess) {
      var data = logRequest?.data?.Results?.[0];

      if (data && data?.Data?.ActionUrl?.includes("identity/administration/ViewBec")) {
        data.Data.ActionUrl = data.Data.ActionUrl.replace(
          "identity/administration/ViewBec",
          "identity/administration/bec/case"
        );
        data.Data.ActionUrl = data.Data.ActionUrl.replace("tenantDomain", "tenantFilter");
      }
      setLogData(data);
      setLookupIp(
        data?.Data?.IP ??
          data?.Data?.PotentialLocationInfo?.RowKey ??
          data?.Data?.RawData?.ClientIP ??
          null
      );
    }
  }, [logRequest.isSuccess]);

  const raw = logData?.Data?.RawData ?? {};
  const user =
    raw.CIPPUserKey ??
    raw.AuditRecord?.CIPPuserId ??
    raw.AuditRecord?.UserKey ??
    raw.UserId ??
    raw.userId;
  const happened = parseAuditTime(raw.CreationTime);
  // The matched alert's conditions, one per line.
  const conditions = String(raw.CIPPClause ?? "")
    .split(" and ")
    .filter(Boolean);
  // Every field of the audit record as a searchable table of field and value.
  const auditFields = Object.entries(raw)
    .filter(([key]) => !excludeProperties.includes(key))
    .map(([key, value]) => {
      const translated = translateAuditLogValue(key, value);
      return {
        Field: getCippTranslation(key),
        Value:
          typeof translated === "boolean"
            ? translated
              ? "Yes"
              : "No"
            : translated !== null && typeof translated === "object"
              ? JSON.stringify(translated)
              : String(translated ?? ""),
      };
    });

  return (
    <Box sx={{ p: 3 }}>
      <Button
        color="inherit"
        onClick={() => router.back()}
        startIcon={
          <SvgIcon fontSize="small">
            <ArrowLeftIcon />
          </SvgIcon>
        }
      >
        Back
      </Button>
      {logRequest.isLoading && <CippFormSkeleton layout={[1, 1, 1]} />}
      {logRequest.isSuccess && logData && (
        <Paper elevation={3} sx={{ mt: 2, p: 3 }}>
          <Stack
            direction={{ xs: "column", md: "row" }}
            spacing={2}
            sx={{ justifyContent: "space-between", alignItems: { md: "center" }, mb: 3 }}
          >
            <Box>
              <Typography variant="h4">{logData.Title}</Typography>
              <Stack direction="row" spacing={1} useFlexGap sx={{ flexWrap: "wrap", mt: 1 }}>
                {logData.AlertType && (
                  <Chip
                    size="small"
                    color={logData.AlertType === "Repeated activity" ? "warning" : "primary"}
                    label={logData.AlertType}
                  />
                )}
                {logData.Workload && (
                  <Chip size="small" variant="outlined" label={logData.Workload} />
                )}
                <Chip
                  size="small"
                  variant="outlined"
                  icon={<CippIcons.Business fontSize="small" />}
                  label={logData.Tenant}
                />
                {happened && (
                  <Tooltip title={happened.toLocaleString()}>
                    <Chip
                      size="small"
                      variant="outlined"
                      icon={<CippIcons.Schedule fontSize="small" />}
                      label={<CippTimeAgo data={happened.toISOString()} />}
                    />
                  </Tooltip>
                )}
              </Stack>
            </Box>
            {logData?.Data?.ActionUrl && logData?.Data?.ActionText && (
              <Button
                variant="contained"
                color="primary"
                startIcon={<CippIcons.Launch />}
                onClick={() => window.open(logData.Data.ActionUrl, "_blank")}
              >
                {logData.Data.ActionText}
              </Button>
            )}
          </Stack>

          <Grid container spacing={2}>
            <Grid size={{ xs: 12, md: lookupIp ? 7 : 12 }}>
              <Card variant="outlined" sx={{ height: "100%" }}>
                <CardHeader title="What happened" />
                <Divider />
                <CardContent>
                  <Stack spacing={2}>
                    <SummaryRow icon={<CippIcons.Bolt fontSize="small" />} label="Activity">
                      <strong>{raw.Operation ?? logData.Operation ?? "Unknown"}</strong>
                    </SummaryRow>
                    <SummaryRow icon={<CippIcons.Person fontSize="small" />} label="Done by">
                      {user ?? "Not recorded"}
                    </SummaryRow>
                    <SummaryRow icon={<CippIcons.AccessTime fontSize="small" />} label="When">
                      {happened ? happened.toLocaleString() : "Not recorded"}
                    </SummaryRow>
                    <SummaryRow icon={<CippIcons.LocationOn fontSize="small" />} label="From">
                      {lookupIp ?? "No IP address recorded"}
                    </SummaryRow>
                    <Divider />
                    <SummaryRow icon={<CippIcons.Rule fontSize="small" />} label="Why it alerted">
                      {conditions.length > 0 ? (
                        <Stack spacing={0.5} sx={{ mt: 0.5 }}>
                          {conditions.map((condition, index) => (
                            <Stack
                              key={index}
                              direction="row"
                              spacing={1}
                              sx={{ alignItems: "center" }}
                            >
                              <CippIcons.CheckCircle color="success" fontSize="small" />
                              <span>{condition}</span>
                            </Stack>
                          ))}
                        </Stack>
                      ) : (
                        "Not recorded"
                      )}
                    </SummaryRow>
                    {raw.CIPPAlertComment && (
                      <SummaryRow
                        icon={<CippIcons.Description fontSize="small" />}
                        label="Alert notes"
                      >
                        {raw.CIPPAlertComment}
                      </SummaryRow>
                    )}
                    <SummaryRow icon={<CippIcons.TaskAlt fontSize="small" />} label="Actions taken">
                      {raw.CIPPAction
                        ? getCippFormatting(raw.CIPPAction, "CIPPAction")
                        : "None"}
                    </SummaryRow>
                  </Stack>
                </CardContent>
              </Card>
            </Grid>

            {lookupIp && (
              <Grid size={{ xs: 12, md: 5 }}>
                <Card variant="outlined" sx={{ height: "100%" }}>
                  <CardHeader title="Where it came from" subheader={lookupIp} />
                  <Divider />
                  <CardContent>
                    <CippGeoLocation ipAddress={lookupIp} />
                  </CardContent>
                </Card>
              </Grid>
            )}
            <Grid size={{ xs: 12 }}>
              <CippAuditLogRuleCheck tenant={logData.Tenant} logId={id} />
            </Grid>
            <Grid size={{ xs: 12 }}>
              <CippDataTable
                title="Everything in the audit record"
                data={auditFields}
                simpleColumns={["Field", "Value"]}
                queryKey={`AuditLogFields-${id}`}
              />
            </Grid>
          </Grid>
        </Paper>
      )}
    </Box>
  );
};

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>;

export default Page;

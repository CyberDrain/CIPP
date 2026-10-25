import { useState } from "react";
import { CippIcons } from "../../../../utils/icon-registry"
import { Layout as DashboardLayout } from "../../../../layouts/index";
import { TabbedLayout } from "../../../../layouts/TabbedLayout";
import { CippTablePage } from "../../../../components/CippComponents/CippTablePage.jsx";
import { CippDateRangeFilter } from "../../../../components/CippComponents/CippDateRangeFilter";
import tabOptions from "./tabOptions.json";
import { useSettings } from "../../../../hooks/use-settings";
import { downloadJson } from "../../../../utils/download-json";

// Saved Logs Configuration
const savedLogsColumns = [
  "Timestamp",
  "Tenant",
  "Title",
  "AlertType",
  "Workload",
  "Operation",
  "User",
  "TimesRepeated",
];
const savedLogsApiUrl = "/api/ListAuditLogs";
const savedLogViewLink = "/tenant/administration/audit-logs/log?id=[LogId]";
const savedLogsActions = [
  {
    label: "View Log",
    link: savedLogViewLink,
    pinned: true,
    color: "primary",
    icon: <CippIcons.EyeIcon />,
  },
  {
    // The full saved logs; the table's CSV and PDF exports hold only the visible columns.
    label: "Download (JSON)",
    noConfirm: true,
    multiPost: true,
    icon: <CippIcons.Download />,
    customFunction: (rows) => {
      const logs = [rows].flat();
      downloadJson(
        logs,
        logs.length === 1 ? `audit-log-${logs[0].LogId}.json` : `audit-logs-${logs.length}.json`
      );
    },
  },
];

const offCanvas = {
  extendedInfoFields: [
    "Timestamp",
    "Tenant",
    "Title",
    "AlertType",
    "Workload",
    "Operation",
    "User",
    "TimesRepeated",
  ],
  actions: savedLogsActions,
};

// An alert is on a single event, or on one user or app repeating an action a set number of times.
const savedLogsFilters = [
  {
    filterName: "Repeated activity alerts",
    value: [{ id: "AlertType", value: "Repeated activity" }],
    type: "column",
  },
  ...["AzureActiveDirectory", "Exchange", "SharePoint", "OneDrive", "MicrosoftTeams"].map(
    (workload) => ({
      filterName: workload,
      value: [{ id: "Workload", value: workload }],
      type: "column",
    })
  ),
];

const Page = () => {
  const tenant = useSettings().currentTenant;
  // Preserves the previous behaviour: RelativeTime defaults to "7d" and is always sent.
  const [apiParams, setApiParams] = useState({ RelativeTime: "7d" });

  const handleApply = ({ RelativeTime, StartDate, EndDate }) => {
    setApiParams({
      RelativeTime: RelativeTime ? RelativeTime : "7d",
      ...(StartDate && { StartDate }),
      ...(EndDate && { EndDate }),
    });
  };

  const searchFilter = (
    <CippDateRangeFilter
      title="Search Options"
      defaultTime={7}
      defaultInterval={{ label: "Days", value: "d" }}
      onApply={handleApply}
    />
  );

  return (
    <CippTablePage
      tableFilter={searchFilter}
      title="Saved Logs"
      apiUrl={savedLogsApiUrl}
      apiDataKey="Results"
      simpleColumns={savedLogsColumns}
      queryKey={`SavedLogs-${tenant}-${apiParams.RelativeTime ?? ""}-${apiParams.StartDate ?? ""}-${
        apiParams.EndDate ?? ""
      }`}
      // Pages through ListAuditLogs via Metadata.nextLink, so a long All Tenants list loads as it arrives.
      apiData={{ ...apiParams, manualPagination: true }}
      actions={savedLogsActions}
      offCanvas={offCanvas}
      filters={savedLogsFilters}
      rowOpen={{
        link: savedLogViewLink,
        condition: (row) => Boolean(row?.LogId),
      }}
    />
  );
};

Page.getLayout = (page) => (
  <DashboardLayout>
    <TabbedLayout tabOptions={tabOptions}>{page}</TabbedLayout>
  </DashboardLayout>
);

export default Page;

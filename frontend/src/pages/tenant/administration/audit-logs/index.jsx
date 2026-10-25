import { useState } from "react";
import { CippIcons } from "../../../../utils/icon-registry"
import { Layout as DashboardLayout } from "../../../../layouts/index";
import { TabbedLayout } from "../../../../layouts/TabbedLayout";
import { CippTablePage } from "../../../../components/CippComponents/CippTablePage.jsx";
import { CippDateRangeFilter } from "../../../../components/CippComponents/CippDateRangeFilter";
import tabOptions from "./tabOptions.json";

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
      queryKey={`SavedLogs-${apiParams.RelativeTime ?? ""}-${apiParams.StartDate ?? ""}-${
        apiParams.EndDate ?? ""
      }`}
      apiData={apiParams}
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

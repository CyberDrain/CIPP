import { Layout as DashboardLayout } from "../../../../layouts/index";
import { CippIcons } from "../../../../utils/icon-registry"
import CippTablePage from "../../../../components/CippComponents/CippTablePage";
import { Button } from "@mui/material";
import Link from "next/link";
import { useSettings } from "../../../../hooks/use-settings.js";
import ScheduledTaskDetails from "../../../../components/CippComponents/ScheduledTaskDetails";
import { ApiGetCall } from "../../../../api/ApiCall";

const Page = () => {
  const initialState = useSettings();
  const currentTenant = initialState.currentTenant;
  // Separate fetch: action conditions only see their own row, and the table's paginated cache is internal
  const vacationTasks = ApiGetCall({
    url: "/api/ListScheduledItems?SearchTitle=*Vacation*",
    data: { tenantFilter: currentTenant },
    queryKey: `VacationModeTasks-${currentTenant}`,
  });

  // A Remove task's start counterpart is "Add ..." ("Create ..." for travel policies) with the same
  // suffix; forwarding appends " -> target" to the Add name only
  const startPending = (removeRow) => {
    const suffix = removeRow.Name.slice("Remove ".length);
    const tasks = Array.isArray(vacationTasks.data) ? vacationTasks.data : [];
    return tasks.some((task) => {
      const startSuffix = task.Name?.replace(/^(Add|Create) /, "");
      return (
        startSuffix !== task.Name &&
        (startSuffix === suffix || startSuffix.startsWith(`${suffix} -> `)) &&
        task.Tenant === removeRow.Tenant &&
        !["Completed", "Failed"].includes(task.TaskState) &&
        new Date(task.ScheduledTime) <= new Date(removeRow.ScheduledTime)
      );
    });
  };

  const actions = [
    {
      label: "View Task Details",
      link: "/cipp/scheduler/task?id=[RowKey]",
      pinned: true,
      icon: <CippIcons.EyeIcon />,
    },
    {
      label: "End Vacation Now",
      type: "POST",
      url: "/api/AddScheduledItem",
      data: { RowKey: "RowKey", RunNow: true },
      confirmText:
        "Run [Name] now? This reverts the vacation change immediately instead of waiting for the end date. Use this when the user is back early.",
      icon: <CippIcons.PlayArrow />,
      multiPost: false,
      // Running the revert before the start task leaves the start change in place with no cleanup
      condition: (row) =>
        vacationTasks.isSuccess &&
        row?.TaskState === "Planned" &&
        row?.Name?.startsWith("Remove ") &&
        !startPending(row),
    },
    {
      label: "Cancel Vacation Mode",
      type: "POST",
      url: "/api/RemoveScheduledItem",
      data: { ID: "RowKey" },
      confirmText:
        "Cancel deletes this scheduled task without reverting anything, so the user might remain in vacation mode permanently. If the user is back early, use 'End Vacation Now' on the Remove task instead.",
      icon: <CippIcons.Delete />,
      multiPost: false,
    },
  ];

  const filterList = [
    {
      filterName: "Running",
      value: [{ id: "TaskState", value: "Running" }],
      type: "column",
    },
    {
      filterName: "Planned",
      value: [{ id: "TaskState", value: "Planned" }],
      type: "column",
    },
    {
      filterName: "Failed",
      value: [{ id: "TaskState", value: "Failed" }],
      type: "column",
    },
    {
      filterName: "Completed",
      value: [{ id: "TaskState", value: "Completed" }],
      type: "column",
    },
    {
      filterName: "CA Exclusion",
      value: [{ id: "Name", value: "CA Exclusion" }],
      type: "column",
    },
    {
      filterName: "Location Alerts",
      value: [{ id: "Name", value: "Location Alert Exclusion" }],
      type: "column",
    },
    {
      filterName: "Mailbox Permissions",
      value: [{ id: "Name", value: "Mailbox Vacation" }],
      type: "column",
    },
    {
      filterName: "Mail Forwarding",
      value: [{ id: "Name", value: "Forwarding Vacation" }],
      type: "column",
    },
    {
      filterName: "Out of Office",
      value: [{ id: "Name", value: "OOO Vacation" }],
      type: "column",
    },
    {
      filterName: "Group Membership",
      value: [{ id: "Name", value: "Group Membership Vacation" }],
      type: "column",
    },
  ];

  return (
    <CippTablePage
      cardButton={
        <Button
          component={Link}
          href="/identity/administration/vacation-mode/add"
          startIcon={<CippIcons.EventAvailable />}
        >
          Add Vacation Schedule
        </Button>
      }
      title="Vacation Mode"
      apiUrl="/api/ListScheduledItems?SearchTitle=*Vacation*"
      queryKey={`VacationMode-${currentTenant}`}
      actions={actions}
      simpleColumns={["Tenant", "Name", "Reference", "TaskState", "ScheduledTime", "ExecutedTime"]}
      filters={filterList}
      offCanvas={{
        children: (extendedData) => (
          <ScheduledTaskDetails data={extendedData} showActions={true} showTitle={false} />
        ),
        size: "xl",
        actions: actions,
      }}
      rowOpen={{
        link: '/cipp/scheduler/task?id=[RowKey]',
        condition: (row) => Boolean(row?.RowKey),
      }}
    />
  );
};

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>;

export default Page;

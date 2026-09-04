import { Layout as DashboardLayout } from "../../../../layouts/index";
import { TabbedLayout } from "../../../../layouts/TabbedLayout";
import tabOptions from "./tabOptions.json";
import { CippIcons } from "../../../../utils/icon-registry"
import CippTablePage from "../../../../components/CippComponents/CippTablePage";
import { Button } from "@mui/material";
import Link from "next/link";

const Page = () => {
  const simpleColumns = [
    "userPrincipalName",
    "displayName",
    "accountEnabled",
    "jitAdminEnabled",
    "jitAdminStartDate",
    "jitAdminExpiration",
    "jitAdminReason",
    "jitAdminCreatedBy",
    "memberOf",
  ];

  const filters = [
    {
      filterName: "Active JIT Admins",
      value: [{ id: "jitAdminEnabled", value: true }],
      type: "column",
    },
    {
      filterName: "Expired/Disabled",
      value: [{ id: "jitAdminEnabled", value: false }],
      type: "column",
    },
  ];

  return (
    <CippTablePage
      cardButton={
        <>
          <Button component={Link} href="jit-admin/add" startIcon={<CippIcons.AdminPanelSettings />}>
            Add JIT Admin
          </Button>
        </>
      }
      title="JIT Admins"
      apiUrl="/api/ListJITAdmin"
      apiDataKey="Results"
      simpleColumns={simpleColumns}
      filters={filters}
    />
  );
};

Page.getLayout = (page) => (
  <DashboardLayout allTenantsSupport={true}>
    <TabbedLayout tabOptions={tabOptions}>{page}</TabbedLayout>
  </DashboardLayout>
);

export default Page;

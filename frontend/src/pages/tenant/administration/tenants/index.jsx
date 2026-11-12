import { Layout as DashboardLayout } from "../../../../layouts/index";
import { TabbedLayout } from "../../../../layouts/TabbedLayout";
import { CippTablePage } from "../../../../components/CippComponents/CippTablePage.jsx";
import { CippIcons } from "../../../../utils/icon-registry"
import { usePermissions } from "../../../../hooks/use-permissions.js";
import tabOptions from "./tabOptions";

const Page = () => {
  const pageTitle = "Tenants";
  const { checkPermissions } = usePermissions();
  // The cloud picks the authority and credentials CIPP uses for the tenant, so the backend holds
  // this to the same bar as adding a tenant (CIPP.AppSettings.ReadWrite + all tenants).
  const canSetCloudEnvironment = checkPermissions(["CIPP.AppSettings.ReadWrite"]);

  const simpleColumns = [
    "displayName",
    "defaultDomainName",
    "cloudEnvironment",
    "tenantGroups",
    "portal_m365",
    "portal_exchange",
    "portal_entra",
    "portal_sharepoint",
    "portal_teams",
    "portal_azure",
    "portal_intune",
    "portal_security",
    "portal_compliance",
    "portal_platform",
    "portal_bi",
  ];

  const actions = [
    {
      label: "Edit Tenant",
      link: "/tenant/manage/edit?tenantFilter=[defaultDomainName]",
      pinned: true,
      icon: <CippIcons.Edit />,
    },
    {
      label: "Configure Backup",
      link: "/tenant/manage/configuration-backup?tenantFilter=[defaultDomainName]",
      icon: <CippIcons.Edit />,
    },
    {
      label: "Set Cloud Environment",
      type: "POST",
      url: "/api/EditTenantCloudEnvironment",
      data: { customerId: "customerId" },
      confirmText:
        "Select the Microsoft cloud [displayName] lives in. This overrides the value detected when the tenant was added. DoD tenants may be detected as GCC High and need to be set here.",
      icon: <CippIcons.Edit />,
      color: "info",
      hideBulk: true,
      condition: () => canSetCloudEnvironment,
      fields: [
        {
          type: "autoComplete",
          name: "cloudEnvironment",
          label: "Cloud Environment",
          multiple: false,
          creatable: false,
          required: true,
          options: [
            { label: "Commercial", value: "Commercial" },
            { label: "US Government (GCC High)", value: "USGovHigh" },
            { label: "US Government (DoD)", value: "USGovDoD" },
          ],
        },
      ],
    },
    {
      label: "Delete Capabilities Cache",
      type: "POST",
      url: "/api/RemoveTenantCapabilitiesCache",
      data: { defaultDomainName: "defaultDomainName" },
      confirmText: "Are you sure you want to delete the capabilities cache for this tenant?",
      color: "info",
      icon: <CippIcons.Delete />,
    },
  ];

  return (
    <CippTablePage
      title={pageTitle}
      tenantInTitle={false}
      simpleColumns={simpleColumns}
      apiUrl="/api/ListTenants"
      queryKey="TenantListPage"
      apiData={{
        Mode: "TenantList",
        tenantFilter: null,
      }}
      actions={actions}
    />
  );
};

Page.getLayout = (page) => (
  <DashboardLayout>
    <TabbedLayout tabOptions={tabOptions}>{page}</TabbedLayout>
  </DashboardLayout>
);

export default Page;

import { Layout as DashboardLayout } from '../../../../layouts/index'
import { TabbedLayout } from '../../../../layouts/TabbedLayout'
import { CippTablePage } from '../../../../components/CippComponents/CippTablePage.jsx'
import { useCippReportDB } from '../../../../components/CippComponents/CippReportDBControls'
import { CippIcons } from '../../../../utils/icon-registry'
import { useSettings } from '../../../../hooks/use-settings'
import { usePermissions } from '../../../../hooks/use-permissions'
import tabOptions from './tabOptions.json'

// A licence a group gives or takes away comes straight back, so those rows cannot be undone here
const GROUP_LICENSING = 'Microsoft Azure AD Group-Based Licensing'

const Page = () => {
  const currentTenant = useSettings().currentTenant
  const canWriteUser = usePermissions().checkPermissions(['Identity.User.ReadWrite'])
  const reportDB = useCippReportDB({
    apiUrl: '/api/ListLicenseChanges',
    queryKey: 'ListLicenseChanges',
    cacheName: 'LicenseChanges',
    syncTitle: 'Sync Licence Changes',
    allowToggle: true,
    defaultCached: false,
  })

  const simpleColumns = [
    ...reportDB.cacheColumns.filter((c) => c === 'Tenant'),
    'activityDateTime',
    'userPrincipalName',
    'change',
    'license',
    'initiatedBy',
    'initiatedByType',
    ...reportDB.cacheColumns.filter((c) => c !== 'Tenant'),
  ]

  const actions = [
    {
      label: 'View User',
      link: '/identity/administration/users/user?userId=[userId]',
      icon: <CippIcons.EyeIcon />,
      condition: (row) => !!row.userId,
    },
    {
      label: 'Undo Change',
      type: 'POST',
      url: '/api/ExecBulkLicense',
      icon: <CippIcons.Undo />,
      multiPost: false,
      hideBulk: true,
      // An older change of the same licence on the same user has been superseded and is not offered
      condition: (row) =>
        canWriteUser &&
        row.latestChange === true &&
        !!row.userId &&
        row.initiatedBy !== GROUP_LICENSING,
      confirmText: (row) =>
        row?.change === 'Added'
          ? 'Remove [license] from [userPrincipalName]? If the user also gets this licence from a group, they keep it.'
          : 'Assign [license] to [userPrincipalName] again? This needs a free licence, and every service in it is switched on.',
      customDataformatter: (row) => ({
        tenantFilter: row.Tenant ?? currentTenant,
        LicenseOperation: row.change === 'Added' ? 'Remove' : 'Add',
        [row.change === 'Added' ? 'LicensesToRemove' : 'Licenses']: [
          { label: row.license, value: row.skuId },
        ],
        userIds: [row.userId],
      }),
      relatedQueryKeys: ['ListLicenseChanges*'],
    },
  ]

  return (
    <>
      <CippTablePage
        title="Licence Changes"
        apiUrl={reportDB.resolvedApiUrl}
        queryKey={reportDB.resolvedQueryKey}
        simpleColumns={simpleColumns}
        actions={actions}
        offCanvas={{ extendedInfoFields: [...simpleColumns, 'skuPartNumber', 'skuId'] }}
        dataSourceControls={reportDB.controls}
      />
      {reportDB.syncDialog}
    </>
  )
}

Page.getLayout = (page) => (
  <DashboardLayout tenantGroupSupport={true}>
    <TabbedLayout tabOptions={tabOptions}>{page}</TabbedLayout>
  </DashboardLayout>
)

export default Page

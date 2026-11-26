import { Layout as DashboardLayout } from '../../../../layouts/index'
import { TabbedLayout } from '../../../../layouts/TabbedLayout'
import { CippTablePage } from '../../../../components/CippComponents/CippTablePage.jsx'
import { useCippReportDB } from '../../../../components/CippComponents/CippReportDBControls'
import tabOptions from './tabOptions.json'

const Page = () => {
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

  return (
    <>
      <CippTablePage
        title="Licence Changes"
        apiUrl={reportDB.resolvedApiUrl}
        queryKey={reportDB.resolvedQueryKey}
        simpleColumns={simpleColumns}
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

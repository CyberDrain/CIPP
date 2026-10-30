import { Button } from '@mui/material'
import { Stack } from '@mui/system'
import Link from 'next/link'
import { CippIcons } from '../../../../utils/icon-registry'
import { CippTablePage } from '../../../../components/CippComponents/CippTablePage.jsx'
import { Layout as DashboardLayout } from '../../../../layouts/index'
import { CippEnrollmentRestrictionDrawer } from '../../../../components/CippComponents/CippEnrollmentRestrictionDrawer.jsx'
import { useSettings } from '../../../../hooks/use-settings'

// Every setting a template keeps, mapped from the row of the same name.
const templateFields = [
  'displayName',
  'description',
  'platform',
  'priority',
  'platformBlocked',
  'personalDeviceEnrollmentBlocked',
  'osMinimumVersion',
  'osMaximumVersion',
  'deviceAdminPlatformBlocked',
  'deviceAdminPersonalDeviceEnrollmentBlocked',
  'deviceAdminOsMinimumVersion',
  'deviceAdminOsMaximumVersion',
  'deviceAdminBlockedManufacturers',
  'AssignTo',
  'customGroup',
]

const Page = () => {
  const pageTitle = 'Enrollment Restrictions'
  const currentTenant = useSettings().currentTenant

  const actions = [
    {
      label: 'Edit Restriction',
      icon: <CippIcons.Edit />,
      hideBulk: true,
      noConfirm: true,
      customComponent: (row, { drawerVisible, setDrawerVisible }) => (
        <CippEnrollmentRestrictionDrawer
          row={row}
          drawerVisible={drawerVisible}
          setDrawerVisible={setDrawerVisible}
        />
      ),
    },
    {
      label: 'Save as Template',
      type: 'POST',
      url: '/api/AddEnrollmentRestrictionTemplate',
      icon: <CippIcons.Book />,
      data: Object.fromEntries(templateFields.map((field) => [field, field])),
      confirmText:
        'Save "[displayName]" as a template? Its groups are saved by name and looked up in each tenant it is deployed to.',
      multiPost: false,
    },
    {
      label: 'Delete Restriction',
      type: 'POST',
      url: '/api/ExecRemoveEnrollmentRestriction',
      icon: <CippIcons.Delete />,
      data: { ids: 'ids', displayName: 'displayName' },
      confirmText:
        'Delete the enrollment restriction "[displayName]"? Users it applies to fall back to the next restriction by priority.',
      color: 'danger',
      multiPost: false,
    },
  ]

  return (
    <CippTablePage
      title={pageTitle}
      apiUrl="/api/ListEnrollmentRestrictions"
      apiDataKey="Results"
      queryKey={`EnrollmentRestrictions-${currentTenant}`}
      actions={actions}
      offCanvas={{
        extendedInfoFields: [
          'displayName',
          'description',
          'platformLabel',
          'priority',
          'PolicyAssignment',
          'ids',
          'lastModifiedDateTime',
        ],
        actions,
      }}
      simpleColumns={['platformLabel', 'priority', 'displayName', 'description', 'PolicyAssignment']}
      cardButton={
        <Stack direction="row" spacing={1}>
          <CippEnrollmentRestrictionDrawer />
          <Button
            component={Link}
            href="/endpoint/autopilot/enrollment-restriction-templates"
            startIcon={<CippIcons.Book />}
          >
            Templates
          </Button>
        </Stack>
      }
    />
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page

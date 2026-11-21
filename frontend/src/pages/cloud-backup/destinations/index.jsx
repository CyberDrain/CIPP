import { Alert, Button, Stack } from '@mui/material'
import Link from 'next/link'
import { CippIcons } from '../../../utils/icon-registry'
import { CippTablePage } from '../../../components/CippComponents/CippTablePage.jsx'
import { Layout as DashboardLayout } from '../../../layouts/index'
import { CippPropertyListCard } from '../../../components/CippCards/CippPropertyListCard'
import { getCippFormatting } from '../../../utils/get-cipp-formatting'
import {
  cloudBackupContentReady,
  cloudBackupProviderLabel,
  cloudBackupSignInLabel,
} from '../../../utils/cloud-backup'

const versioningLabel = (lastTest) => {
  const ready = cloudBackupContentReady(lastTest)
  if (ready === true) return 'On'
  if (ready === false) return 'Off'
  return lastTest ? 'Unknown' : 'Not tested'
}

const RELATED_KEYS = [
  'ListCloudBackupDestinations*',
  'ListCloudBackupOverview*',
]

const toDisplayRow = (row) => ({
  ...row,
  CloudBackupProviderName: cloudBackupProviderLabel(row.Provider),
  CloudBackupLastTest: row.LastTestStatus,
  CloudBackupLastTested: row.LastTestedAt,
  CloudBackupPolicyCount: row.PolicyCount,
  CloudBackupVersioning: versioningLabel(row.LastTest),
  CloudBackupSignIn: cloudBackupSignInLabel(row),
})

const checkResult = (value) =>
  value === true
    ? getCippFormatting('Passed', 'CloudBackupStatus')
    : value === false
      ? getCippFormatting('Failed', 'CloudBackupStatus')
      : 'Not tested'

const actions = [
  {
    label: 'Test Connection',
    type: 'POST',
    url: '/api/ExecCloudBackupDestination',
    icon: <CippIcons.FactCheck />,
    data: { Action: '!Test', Id: 'Id' },
    confirmText:
      'Test [Name]? CIPP writes, reads and deletes a small test file, checks it can manage the retention rule, and checks that versioning is on.',
    relatedQueryKeys: RELATED_KEYS,
  },
  {
    label: 'Edit Destination',
    pinned: true,
    icon: <CippIcons.Edit />,
    link: '/cloud-backup/destinations/edit?id=[Id]',
  },
  {
    label: 'Delete Destination',
    type: 'POST',
    url: '/api/ExecCloudBackupDestination',
    icon: <CippIcons.Delete />,
    data: { Action: '!Delete', Id: 'Id' },
    confirmText:
      'Delete [Name]? The stored secret is removed from CIPP. Backups already in the storage account or bucket are not deleted. A destination used by a policy cannot be deleted.',
    relatedQueryKeys: RELATED_KEYS,
  },
]

const Page = () => {
  const offCanvas = {
    children: (row) => {
      const lastTest = row.LastTest ?? {}
      const errors = Array.isArray(lastTest.Errors) ? lastTest.Errors : []
      return (
        <Stack spacing={2}>
          <CippPropertyListCard
            cardSx={{ p: 0, m: -2 }}
            title={row.Name ? `Destination: ${row.Name}` : 'Destination'}
            actionItems={actions}
            data={row}
            propertyItems={[
              {
                label: 'Provider',
                value: cloudBackupProviderLabel(row.Provider),
              },
              { label: 'Location', value: row.Location },
              {
                label: 'Used by policies',
                value: String(row.PolicyCount ?? 0),
              },
              {
                label: 'Sign-in method',
                value: cloudBackupSignInLabel(row),
              },
              ...(row.ProvisionedBy === 'CIPP'
                ? [{ label: 'Set up by', value: 'Created by CIPP' }]
                : []),
              ...(Number(row.ImmutabilityDays) > 0
                ? [
                    {
                      label: 'Immutable for',
                      value: `${row.ImmutabilityDays} days`,
                    },
                  ]
                : []),
              {
                label: 'Secret',
                value:
                  row.AuthMode === 'CippApp'
                    ? 'Not needed'
                    : row.SecretSet
                      ? 'Stored in Key Vault'
                      : 'Not set',
              },
            ]}
          />
          <CippPropertyListCard
            title="Last Connection Test"
            propertyItems={
              row.LastTestedAt
                ? [
                    {
                      label: 'Tested',
                      value: getCippFormatting(
                        row.LastTestedAt,
                        'CloudBackupLastTested'
                      ),
                    },
                    {
                      label: 'Write a file',
                      value: checkResult(lastTest.Write),
                    },
                    {
                      label: 'Read it back',
                      value: checkResult(lastTest.Read),
                    },
                    { label: 'Delete it', value: checkResult(lastTest.Delete) },
                    {
                      label: 'Manage retention rule',
                      value: checkResult(lastTest.Lifecycle),
                    },
                    ...(lastTest.VersionDelete === undefined ||
                    lastTest.VersionDelete === null
                      ? []
                      : [
                          {
                            label: 'Can remove expired versions',
                            value: checkResult(lastTest.VersionDelete),
                          },
                        ]),
                    {
                      label: 'Versioning',
                      value: versioningLabel(lastTest),
                    },
                    {
                      label: 'Ready for content backup',
                      value:
                        cloudBackupContentReady(lastTest) === true
                          ? getCippFormatting('Passed', 'CloudBackupStatus')
                          : getCippFormatting('Failed', 'CloudBackupStatus'),
                    },
                  ]
                : [
                    {
                      label: 'Tested',
                      value: 'Never. Use Test Connection to check it.',
                    },
                  ]
            }
          />
          {row.LastTestedAt && cloudBackupContentReady(lastTest) !== true && (
            <Alert severity="warning">
              Content backup needs versioning on this storage account or bucket.
              Turn it on in the Azure portal or with your S3 provider, then use
              Test Connection again. Policies can't use this destination until
              then.
            </Alert>
          )}
          {errors.map((error, index) => (
            <Alert severity="error" key={index}>
              {error}
            </Alert>
          ))}
        </Stack>
      )
    },
  }

  return (
    <CippTablePage
      title="Backup Destinations"
      apiUrl="/api/ListCloudBackupDestinations"
      apiData={{ tenantFilter: undefined, tenantGroup: undefined }}
      queryKey="ListCloudBackupDestinations"
      tenantInTitle={false}
      actions={actions}
      offCanvas={offCanvas}
      offCanvasOnRowClick={true}
      dataMap={toDisplayRow}
      cardButton={
        <Button
          component={Link}
          href="/cloud-backup/destinations/add"
          startIcon={<CippIcons.AddBox />}
        >
          Add Destination
        </Button>
      }
      simpleColumns={[
        'Name',
        'CloudBackupProviderName',
        'CloudBackupSignIn',
        'Location',
        'CloudBackupLastTest',
        'CloudBackupLastTested',
        'CloudBackupVersioning',
        'CloudBackupPolicyCount',
      ]}
    />
  )
}

Page.getLayout = (page) => (
  <DashboardLayout usesTenant={false}>{page}</DashboardLayout>
)

export default Page

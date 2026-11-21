import { useEffect, useState } from 'react'
import {
  Alert,
  Button,
  Card,
  CardContent,
  CardHeader,
  Stack,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableRow,
} from '@mui/material'
import Link from 'next/link'
import { CippIcons } from '../../../utils/icon-registry'
import { CippTablePage } from '../../../components/CippComponents/CippTablePage.jsx'
import { Layout as DashboardLayout } from '../../../layouts/index'
import { CippPropertyListCard } from '../../../components/CippCards/CippPropertyListCard'
import { CippApiDialog } from '../../../components/CippComponents/CippApiDialog'
import { CippDataTable } from '../../../components/CippTable/CippDataTable'
import { ApiGetCall } from '../../../api/ApiCall'
import { useSettings } from '../../../hooks/use-settings'
import { useDialog } from '../../../hooks/use-dialog'
import { getCippFormatting } from '../../../utils/get-cipp-formatting'
import {
  cloudBackupPermissionRows,
  cloudBackupPermissionSummary,
  cloudBackupPolicyExclusions,
  cloudBackupPolicyWorkloads,
  cloudBackupScheduleLabel,
  cloudBackupWorkloadLabel,
  parseCloudBackupObject,
} from '../../../utils/cloud-backup'

const RELATED_KEYS = [
  'ListCloudBackupPolicies*',
  'ListCloudBackupOverview*',
  'ListCloudBackupUnusedPermissions*',
]

const toDisplayRow = (row) => ({
  ...row,
  CloudBackupWorkloads: cloudBackupPolicyWorkloads(row)
    .map(cloudBackupWorkloadLabel)
    .join(', '),
  CloudBackupDestinationName: row.DestinationName,
  CloudBackupTenantSummary: row.TenantSummary,
  CloudBackupPermissions: cloudBackupPermissionSummary(row),
  CloudBackupLastResult: row.LastRunStatus,
  CloudBackupLastRun: row.LastRunAt,
})

const cloudBackupPolicyActions = [
  {
    label: 'Edit Policy',
    pinned: true,
    icon: <CippIcons.Edit />,
    link: '/cloud-backup/policies/edit?id=[Id]',
  },
  {
    label: 'Run Backup Now',
    type: 'POST',
    url: '/api/ExecCloudBackupRun',
    icon: <CippIcons.PlayArrow />,
    data: { PolicyId: 'Id' },
    confirmText:
      'Back up every tenant and service in [Name] now? The schedule is not changed. Progress shows on the Runs page.',
    relatedQueryKeys: [...RELATED_KEYS, 'ListCloudBackupRuns*'],
  },
  {
    label: 'Grant Permissions',
    type: 'POST',
    url: '/api/ExecCloudBackupPolicy',
    icon: <CippIcons.VpnKey />,
    data: { Action: '!GrantPermissions', Id: 'Id' },
    confirmText:
      'Give CIPP the Microsoft Graph permissions [Name] needs in every tenant of the policy again? Use this after fixing a tenant whose permissions failed.',
    relatedQueryKeys: RELATED_KEYS,
  },
  {
    label: 'View Runs',
    icon: <CippIcons.History />,
    link: '/cloud-backup/runs?PolicyId=[Id]',
  },
  {
    label: 'Rotate Encryption Key',
    type: 'POST',
    url: '/api/ExecCloudBackupPolicy',
    icon: <CippIcons.VpnKey />,
    data: { Action: '!RotateKey', Id: 'Id' },
    confirmText:
      'Create a new encryption key for [Name]? New backups use the new key. Older backups stay readable with the previous keys, which are kept.',
    condition: (row) => row.Encryption === true,
    relatedQueryKeys: RELATED_KEYS,
  },
  {
    label: 'Delete Policy',
    type: 'POST',
    url: '/api/ExecCloudBackupPolicy',
    icon: <CippIcons.Delete />,
    data: { Action: '!Delete', Id: 'Id' },
    confirmText:
      'Delete [Name]? Scheduled backups stop and the retention rule is removed from the destination. Backups already stored are not deleted.',
    relatedQueryKeys: RELATED_KEYS,
  },
]

const PolicyPermissions = ({ row }) => {
  const dialog = useDialog()
  const tenants = ApiGetCall({
    url: '/api/ListTenants',
    queryKey: 'ListTenants-cloudBackupPermissions',
  })
  const names = {}
  ;(Array.isArray(tenants.data) ? tenants.data : []).forEach((tenant) => {
    names[tenant.customerId] = tenant.displayName
      ? `${tenant.displayName} (${tenant.defaultDomainName})`
      : tenant.defaultDomainName
  })
  ;(row.Tenants ?? []).forEach((tenant) => {
    const customerId = tenant?.addedFields?.customerId
    if (customerId && !names[customerId]) names[customerId] = tenant.label
  })
  const rows = cloudBackupPermissionRows(row)

  return (
    <Card>
      <CardHeader
        title="Permissions per tenant"
        subheader="CIPP gives its own app the Microsoft Graph permissions the policy's services need in each tenant."
      />
      <CardContent sx={{ p: 0, overflowX: 'auto' }}>
        {rows.length === 0 ? (
          <Alert severity="info" sx={{ m: 2 }}>
            Permissions haven't been granted yet. Use Grant Permissions to do it
            now.
          </Alert>
        ) : (
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>Tenant</TableCell>
                <TableCell>Result</TableCell>
                <TableCell>Checked</TableCell>
                <TableCell />
              </TableRow>
            </TableHead>
            <TableBody>
              {rows.map((entry) => {
                const tenantName = names[entry.customerId] ?? entry.customerId
                return (
                  <TableRow key={entry.customerId}>
                    <TableCell>
                      {tenantName}
                      {entry.Message && entry.Status !== 'Granted' && (
                        <Alert
                          severity={
                            entry.Status === 'Failed' ? 'error' : 'info'
                          }
                          sx={{ mt: 1 }}
                        >
                          {entry.Message}
                        </Alert>
                      )}
                    </TableCell>
                    <TableCell>
                      {getCippFormatting(entry.Status, 'CloudBackupPermission')}
                    </TableCell>
                    <TableCell>
                      {entry.CheckedAt
                        ? getCippFormatting(
                            entry.CheckedAt,
                            'CloudBackupLastTested'
                          )
                        : 'Not yet'}
                    </TableCell>
                    <TableCell align="right">
                      {entry.Status !== 'Granted' && (
                        <Button
                          size="small"
                          onClick={() =>
                            dialog.handleOpen({
                              Id: row.Id,
                              TenantId: entry.customerId,
                              TenantName: tenantName,
                            })
                          }
                        >
                          Grant again
                        </Button>
                      )}
                    </TableCell>
                  </TableRow>
                )
              })}
            </TableBody>
          </Table>
        )}
      </CardContent>
      <CippApiDialog
        createDialog={dialog}
        title="Grant Permissions"
        row={dialog.data ?? {}}
        api={{
          type: 'POST',
          url: '/api/ExecCloudBackupPolicy',
          data: { Action: '!GrantPermissions', Id: 'Id', TenantId: 'TenantId' },
          confirmText:
            'Give CIPP the Microsoft Graph permissions this policy needs in [TenantName] again?',
          relatedQueryKeys: RELATED_KEYS,
        }}
      />
    </Card>
  )
}

const PolicyDetails = ({ row }) => {
  const workloads = cloudBackupPolicyWorkloads(row)
  const schedules = parseCloudBackupObject(row.Schedules)
  const nextRuns = parseCloudBackupObject(row.NextRuns)
  const exclusions = cloudBackupPolicyExclusions(row)
  const listOrNone = (items) => (items.length ? items.join(', ') : 'None')

  return (
    <Stack spacing={2}>
      <CippPropertyListCard
        cardSx={{ p: 0, m: -2 }}
        title={row.Name ? `Policy: ${row.Name}` : 'Backup Policy'}
        actionItems={cloudBackupPolicyActions}
        data={row}
        propertyItems={[
          { label: 'Status', value: row.Enabled ? 'Enabled' : 'Disabled' },
          {
            label: 'Destination',
            value: row.DestinationName ?? 'Destination not found',
          },
          { label: 'Tenants', value: row.TenantSummary },
          {
            label: 'Keep earlier versions for',
            value: `${row.RetentionDays} days`,
          },
          {
            label: 'Encryption',
            value: row.Encryption
              ? `On (${row.KeyCount ?? 0} ${row.KeyCount === 1 ? 'key' : 'keys'})`
              : 'Off',
          },
          {
            label: 'Last run',
            value: row.LastRunAt
              ? getCippFormatting(row.LastRunAt, 'CloudBackupLastRun')
              : 'Never',
          },
          {
            label: 'Last run result',
            value: row.LastRunStatus
              ? getCippFormatting(row.LastRunStatus, 'CloudBackupLastResult')
              : 'Not run yet',
          },
        ]}
      />
      <CippPropertyListCard
        title="Services and schedules"
        propertyItems={
          workloads.length
            ? workloads.map((workload) => ({
                label: cloudBackupWorkloadLabel(workload),
                value: (
                  <>
                    {cloudBackupScheduleLabel(schedules[workload]) ??
                      'No schedule'}
                    {', next run '}
                    {nextRuns[workload]
                      ? getCippFormatting(
                          nextRuns[workload],
                          'CloudBackupNextRun'
                        )
                      : 'not scheduled'}
                  </>
                ),
              }))
            : [{ label: 'Services', value: 'None selected' }]
        }
      />
      <CippPropertyListCard
        title="Exclusions"
        propertyItems={[
          { label: 'Users', value: listOrNone(exclusions.Users) },
          { label: 'Groups', value: listOrNone(exclusions.Groups) },
          { label: 'Sites', value: listOrNone(exclusions.Sites) },
        ]}
      />
      <PolicyPermissions row={row} />
    </Stack>
  )
}

const UnusedPermissions = ({ tenant }) => {
  const unused = ApiGetCall({
    url: '/api/ListCloudBackupUnusedPermissions',
    data: { tenantFilter: tenant, InvalidateCIPPCache: true },
    queryKey: `ListCloudBackupUnusedPermissions-${tenant}`,
  })
  const rows = Array.isArray(unused.data) ? unused.data : []
  const [shownFor, setShownFor] = useState(null)
  useEffect(() => {
    if (rows.length > 0) setShownFor(tenant)
  }, [rows.length, tenant])
  if (rows.length === 0 && shownFor !== tenant) return null
  return (
    <Stack spacing={1}>
      {rows.length === 0 ? (
        <Alert severity="success">
          No cloud backup permissions are left to revoke.
        </Alert>
      ) : (
        <Alert severity="info">
          CIPP still has the Microsoft Graph permissions it was given for cloud
          backup in {rows.length === 1 ? 'this tenant' : 'these tenants'}, but
          no policy backs {rows.length === 1 ? 'it' : 'them'} up any more.
          Revoke them unless you plan to add the tenant to a policy again.
          Permissions CIPP needs for its other features are kept.
        </Alert>
      )}
      <CippDataTable
        title="Permissions No Policy Needs"
        data={rows.map((row) => ({
          ...row,
          CloudBackupPermissions: (row.Permissions ?? []).join(', '),
          CloudBackupGrantedAt: row.GrantedAt,
        }))}
        isFetching={unused.isFetching}
        refreshFunction={unused.refetch}
        queryKey={`ListCloudBackupUnusedPermissions-${tenant}-table`}
        simpleColumns={[
          'Tenant',
          'CloudBackupPermissions',
          'CloudBackupGrantedAt',
        ]}
        actions={[
          {
            label: 'Revoke Permissions',
            type: 'POST',
            url: '/api/ExecCloudBackupRevokePermissions',
            icon: <CippIcons.Delete />,
            data: { TenantId: 'TenantId' },
            confirmText:
              'Remove the cloud backup permissions from CIPP in [Tenant]? If you add the tenant to a policy later, CIPP grants them again.',
            relatedQueryKeys: ['ListCloudBackupUnusedPermissions*'],
          },
        ]}
      />
    </Stack>
  )
}

const Page = () => {
  const tenant = useSettings().currentTenant
  return (
    <CippTablePage
      title="Backup Policies"
      apiUrl="/api/ListCloudBackupPolicies"
      apiData={{ InvalidateCIPPCache: true }}
      queryKey={`ListCloudBackupPolicies-${tenant}`}
      tableFilter={<UnusedPermissions tenant={tenant} />}
      actions={cloudBackupPolicyActions}
      offCanvas={{
        title: 'Backup Policy Details',
        children: (row) => <PolicyDetails row={row} />,
      }}
      offCanvasOnRowClick={true}
      dataMap={toDisplayRow}
      cardButton={
        <Button
          component={Link}
          href="/cloud-backup/policies/add"
          startIcon={<CippIcons.AddBox />}
        >
          Add Policy
        </Button>
      }
      simpleColumns={[
        'Name',
        'Enabled',
        'CloudBackupDestinationName',
        'CloudBackupTenantSummary',
        'CloudBackupWorkloads',
        'CloudBackupPermissions',
        'CloudBackupLastResult',
        'CloudBackupLastRun',
      ]}
    />
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page

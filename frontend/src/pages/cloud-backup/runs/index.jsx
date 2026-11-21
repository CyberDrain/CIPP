import { useEffect } from 'react'
import { useRouter } from 'next/router'
import { useForm, useWatch } from 'react-hook-form'
import { Alert, Card, CardContent, Stack } from '@mui/material'
import { CippTablePage } from '../../../components/CippComponents/CippTablePage.jsx'
import { Layout as DashboardLayout } from '../../../layouts/index'
import { CippPropertyListCard } from '../../../components/CippCards/CippPropertyListCard'
import { CippDataTable } from '../../../components/CippTable/CippDataTable'
import CippFormComponent from '../../../components/CippComponents/CippFormComponent'
import { ApiGetCall } from '../../../api/ApiCall'
import { useSettings } from '../../../hooks/use-settings'
import { getCippFormatting } from '../../../utils/get-cipp-formatting'
import { formatBytes } from '../../../utils/instance-diagnostics'
import {
  cloudBackupWorkloadLabel,
  cloudBackupWorkloadSources,
  parseCloudBackupList,
  toCloudBackupRunRow,
} from '../../../utils/cloud-backup'

const formatDuration = (seconds) => {
  const total = Number(seconds)
  if (!Number.isFinite(total) || total < 0) return 'Still running'
  if (total < 60) return `${Math.round(total)} seconds`
  const minutes = Math.floor(total / 60)
  if (minutes < 60) {
    const rest = Math.round(total % 60)
    return rest ? `${minutes} min ${rest} s` : `${minutes} min`
  }
  const hours = Math.floor(minutes / 60)
  const restMinutes = minutes % 60
  return restMinutes ? `${hours} h ${restMinutes} min` : `${hours} h`
}

const firstNumber = (...values) => {
  const value = values.find((item) => item !== undefined && item !== null)
  return value === undefined ? undefined : Number(value)
}

const sourceCounts = (row) => ({
  total: firstNumber(row.Owners, row.OwnerCount),
  failed: firstNumber(row.OwnersFailed, row.FailedOwners),
})

const toDisplayRow = (row) => {
  const { total } = sourceCounts(row)
  return {
    ...toCloudBackupRunRow(row),
    CloudBackupSources: total,
    Duration: row.CompletedAt
      ? formatDuration(row.DurationSeconds)
      : 'Still running',
  }
}

const toOwnerRow = (owner) => {
  const warnings = parseCloudBackupList(owner.Warnings)
  return {
    ...owner,
    CloudBackupSource:
      owner.DisplayName ??
      owner.UserPrincipalName ??
      owner.SiteUrl ??
      owner.OwnerId ??
      owner.RowKey,
    CloudBackupStatus: owner.Status,
    CloudBackupSize: owner.Bytes,
    CloudBackupDeleted: owner.Deleted ?? 0,
    CloudBackupWarnings: warnings.join(' | '),
  }
}

const RunSources = ({ row }) => {
  const runId = row.RunId ?? row.Id
  const owners = ApiGetCall({
    url: '/api/ListCloudBackupRunOwners',
    data: { RunId: runId },
    queryKey: `ListCloudBackupRunOwners-${runId}`,
    waiting: !!runId,
  })
  const rows = Array.isArray(owners.data) ? owners.data.map(toOwnerRow) : []

  if (owners.isError) {
    return (
      <Alert severity="error">
        The results for this run could not be loaded. Close the details and open
        them again to retry.
      </Alert>
    )
  }

  return (
    <CippDataTable
      title={`${cloudBackupWorkloadSources(row.Workload)} in this run`}
      data={rows}
      isFetching={owners.isFetching}
      refreshFunction={owners.refetch}
      queryKey={`ListCloudBackupRunOwners-${runId}-table`}
      simpleColumns={[
        'CloudBackupSource',
        'CloudBackupStatus',
        'Items',
        'CloudBackupSize',
        'CloudBackupDeleted',
        'CloudBackupWarnings',
      ]}
      filters={[
        {
          filterName: 'Failed',
          value: [{ id: 'CloudBackupStatus', value: 'Failed' }],
          type: 'column',
        },
      ]}
    />
  )
}

const RunDetails = ({ row }) => {
  const warnings = parseCloudBackupList(row.Warnings)
  const { total, failed } = sourceCounts(row)
  const sourcesLabel = cloudBackupWorkloadSources(row.Workload)
  return (
    <Stack spacing={2}>
      <CippPropertyListCard
        cardSx={{ p: 0, m: -2 }}
        title={
          row.Workload
            ? `${cloudBackupWorkloadLabel(row.Workload)} backup of ${row.Tenant}`
            : `Backup of ${row.Tenant}`
        }
        propertyItems={[
          { label: 'Policy', value: row.PolicyName },
          { label: 'Tenant', value: row.Tenant },
          {
            label: 'Service',
            value: row.Workload
              ? cloudBackupWorkloadLabel(row.Workload)
              : 'Unknown',
          },
          {
            label: 'Result',
            value: getCippFormatting(row.Status, 'CloudBackupStatus'),
          },
          {
            label: 'Started',
            value: getCippFormatting(row.StartedAt, 'CloudBackupStartedAt'),
          },
          {
            label: 'Finished',
            value: row.CompletedAt
              ? getCippFormatting(row.CompletedAt, 'CloudBackupCompletedAt')
              : 'Still running',
          },
          { label: 'Duration', value: toDisplayRow(row).Duration },
          {
            label: sourcesLabel,
            value:
              total === undefined
                ? 'Unknown'
                : failed
                  ? `${total} (${failed} failed)`
                  : String(total),
          },
          { label: 'Items backed up', value: String(row.Items ?? 0) },
          { label: 'Size', value: formatBytes(row.Bytes) },
        ]}
      />
      {warnings.map((warning, index) => (
        <Alert severity="warning" key={index}>
          {warning}
        </Alert>
      ))}
      <Card>
        <CardContent sx={{ p: 0 }}>
          <RunSources row={row} />
        </CardContent>
      </Card>
    </Stack>
  )
}

const Page = () => {
  const router = useRouter()
  const tenant = useSettings().currentTenant
  const formControl = useForm({ defaultValues: { PolicyId: null } })
  const policyId = useWatch({ control: formControl.control, name: 'PolicyId' })

  useEffect(() => {
    if (router.query.PolicyId) {
      formControl.setValue('PolicyId', router.query.PolicyId)
    }
  }, [router.query.PolicyId, formControl])

  const policies = ApiGetCall({
    url: '/api/ListCloudBackupPolicies',
    data: { tenantFilter: tenant, InvalidateCIPPCache: true },
    queryKey: `ListCloudBackupPolicies-picker-${tenant}`,
  })
  const policyOptions = (Array.isArray(policies.data) ? policies.data : []).map(
    (policy) => ({
      label: policy.Name,
      value: policy.Id,
    })
  )

  const filter = (
    <Card>
      <CardContent>
        <CippFormComponent
          type="select"
          label="Show runs for policy"
          name="PolicyId"
          formControl={formControl}
          options={policyOptions}
          isFetching={policies.isFetching}
          placeholder="All policies"
        />
      </CardContent>
    </Card>
  )

  return (
    <CippTablePage
      title="Backup Runs"
      apiUrl="/api/ListCloudBackupRuns"
      apiData={{ PolicyId: policyId || undefined, InvalidateCIPPCache: true }}
      queryKey={`ListCloudBackupRuns-${tenant}-${policyId || 'all'}`}
      tableFilter={filter}
      dataMap={toDisplayRow}
      offCanvas={{
        title: 'Backup Run Details',
        size: 'xl',
        children: (row) => <RunDetails row={row} />,
      }}
      offCanvasOnRowClick={true}
      simpleColumns={[
        'CloudBackupStartedAt',
        'PolicyName',
        'Tenant',
        'CloudBackupWorkload',
        'CloudBackupStatus',
        'CloudBackupSources',
        'Items',
        'CloudBackupSize',
        'Duration',
      ]}
      filters={[
        {
          filterName: 'Failed',
          value: [{ id: 'CloudBackupStatus', value: 'Failed' }],
          type: 'column',
        },
        {
          filterName: 'Running',
          value: [{ id: 'CloudBackupStatus', value: 'Running' }],
          type: 'column',
        },
      ]}
    />
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page

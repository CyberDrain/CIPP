import { useMemo } from 'react'
import { Alert, Button, Container, Stack } from '@mui/material'
import Link from 'next/link'
import { Layout as DashboardLayout } from '../../../layouts/index'
import { CippHead } from '../../../components/CippComponents/CippHead'
import { CippInfoBar } from '../../../components/CippCards/CippInfoBar'
import { CippDataTable } from '../../../components/CippTable/CippDataTable'
import { ApiGetCall } from '../../../api/ApiCall'
import { useSettings } from '../../../hooks/use-settings'
import { CippIcons } from '../../../utils/icon-registry'
import { formatBytes } from '../../../utils/instance-diagnostics'
import {
  CLOUD_BACKUP_WORKLOADS,
  cloudBackupWorkloadLabel,
  parseCloudBackupObject,
  toCloudBackupRunRow,
} from '../../../utils/cloud-backup'

const toWorkloadRows = (workloads) => {
  const entries = Array.isArray(workloads)
    ? workloads.map((entry) => [entry?.Workload, entry])
    : Object.entries(parseCloudBackupObject(workloads))
  const byWorkload = new Map(
    entries
      .filter(([workload]) => workload)
      .map(([workload, entry]) => [String(workload).toLowerCase(), entry ?? {}])
  )
  return CLOUD_BACKUP_WORKLOADS.filter(({ value }) =>
    byWorkload.has(value)
  ).map(({ value }) => {
    const entry = byWorkload.get(value)
    return {
      ...entry,
      Workload: value,
      CloudBackupWorkload: cloudBackupWorkloadLabel(value),
      CloudBackupSources: entry.Sources ?? entry.Owners ?? entry.OwnerCount,
      CloudBackupSize: entry.Bytes,
      CloudBackupLastRun: entry.LastRunAt,
      CloudBackupLastResult: entry.LastRunStatus,
      CloudBackupFailures24h: entry.Failures24h ?? 0,
    }
  })
}

const Page = () => {
  const tenant = useSettings().currentTenant
  const overview = ApiGetCall({
    url: '/api/ListCloudBackupOverview',
    data: { tenantFilter: tenant, InvalidateCIPPCache: true },
    queryKey: `ListCloudBackupOverview-${tenant}`,
  })
  const data = overview.data ?? {}
  const latestRuns = useMemo(
    () =>
      Array.isArray(data.LatestRuns)
        ? data.LatestRuns.map(toCloudBackupRunRow)
        : [],
    [data.LatestRuns]
  )
  const workloadRows = useMemo(
    () => toWorkloadRows(data.Workloads),
    [data.Workloads]
  )

  const stats = [
    {
      name: 'Policies',
      data: data.Policies ?? 0,
      icon: <CippIcons.Policy />,
      link: '/cloud-backup/policies',
    },
    {
      name: 'Enabled policies',
      data: data.EnabledPolicies ?? 0,
      icon: <CippIcons.CheckCircle />,
      link: '/cloud-backup/policies',
    },
    {
      name: 'Destinations',
      data: data.Destinations ?? 0,
      icon: <CippIcons.Storage />,
      link: '/cloud-backup/destinations',
    },
    {
      name: 'Tenants covered',
      data: data.TenantsCovered ?? 0,
      icon: <CippIcons.Groups />,
    },
    {
      name: 'Failures (24 hours)',
      data: data.Failures24h ?? 0,
      icon: <CippIcons.Error />,
      color: data.Failures24h > 0 ? 'error' : 'primary',
      link: '/cloud-backup/runs',
    },
    {
      name: 'Size of latest runs',
      data: formatBytes(data.LatestBytes),
      icon: <CippIcons.Backup />,
    },
  ]

  return (
    <>
      <CippHead title="Cloud Backup" />
      <Container maxWidth={false}>
        <Stack spacing={2}>
          {overview.isSuccess && !data.Destinations && (
            <Alert
              severity="info"
              action={
                <Button
                  component={Link}
                  href="/cloud-backup/destinations/add"
                  color="inherit"
                  size="small"
                >
                  Add destination
                </Button>
              }
            >
              Start by adding a destination: the Azure storage account or S3
              bucket where backups are stored.
            </Alert>
          )}
          {overview.isSuccess && !!data.Destinations && !data.Policies && (
            <Alert
              severity="info"
              action={
                <Button
                  component={Link}
                  href="/cloud-backup/policies/add"
                  color="inherit"
                  size="small"
                >
                  Add policy
                </Button>
              }
            >
              Add a backup policy to choose which tenants and services are
              backed up, and how often.
            </Alert>
          )}
          {overview.isError && (
            <Alert severity="error">
              The backup overview could not be loaded. Refresh the page to try
              again.
            </Alert>
          )}
          <CippInfoBar data={stats} isFetching={overview.isFetching} />
          <CippDataTable
            title="By service"
            data={workloadRows}
            isFetching={overview.isFetching}
            refreshFunction={overview.refetch}
            queryKey="ListCloudBackupOverview-workloads"
            simpleColumns={[
              'CloudBackupWorkload',
              'CloudBackupSources',
              'Items',
              'CloudBackupSize',
              'CloudBackupFailures24h',
              'CloudBackupLastResult',
              'CloudBackupLastRun',
            ]}
          />
          <CippDataTable
            title="Latest backup per tenant and service"
            data={latestRuns}
            isFetching={overview.isFetching}
            refreshFunction={overview.refetch}
            queryKey="ListCloudBackupOverview-latest"
            simpleColumns={[
              'Tenant',
              'PolicyName',
              'CloudBackupWorkload',
              'CloudBackupStatus',
              'CloudBackupCompletedAt',
              'Items',
              'CloudBackupSize',
            ]}
          />
        </Stack>
      </Container>
    </>
  )
}

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>

export default Page

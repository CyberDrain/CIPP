import { useMemo } from 'react'
import { Chip, Stack } from '@mui/material'
import { Layout as DashboardLayout } from '../../../../layouts/index'
import { TabbedLayout } from '../../../../layouts/TabbedLayout'
import { CippTablePage } from '../../../../components/CippComponents/CippTablePage.jsx'
import {
  auditLogFeedFilters,
  auditLogFeedOffCanvas,
} from '../../../../components/CippComponents/CippAuditLogFeedDetails'
import tabOptions from './tabOptions.json'
import { useSettings } from '../../../../hooks/use-settings'
import { ApiGetCall } from '../../../../api/ApiCall'

// One row per tenant and log: how far CIPP has collected it for alerting, and any problem with what to do.
const apiUrl = '/api/ListAuditLogFeedStatus'

const simpleColumns = [
  'Tenant',
  'Log',
  'Status',
  'CheckedUpToDateTime',
  'DelayMinutes',
  'Problem',
  'WhatToDo',
  'BatchesWaiting',
  'BatchesFailing',
]

const Page = () => {
  const tenant = useSettings().currentTenant

  // The summary's own plain query: the table's query is paged, so the two cannot share a key.
  const query = ApiGetCall({
    url: apiUrl,
    data: { tenantFilter: tenant },
    queryKey: `AuditLogFeedStatus-${tenant}`,
    waiting: !!tenant,
  })

  const summary = useMemo(() => {
    const rows = Array.isArray(query.data) ? query.data : []
    const count = (status) => rows.filter((row) => row.Status === status).length
    return {
      total: rows.length,
      upToDate: count('Up to date'),
      delayed: count('Delayed'),
      errors: count('Error, retrying'),
      waiting: count('Waiting to start'),
    }
  }, [query.data])

  const tableFilter = !query.isFetching && summary.total > 0 && (
    <Stack direction="row" spacing={1} useFlexGap sx={{ flexWrap: 'wrap' }}>
      <Chip
        size="small"
        color={summary.upToDate === summary.total ? 'success' : 'warning'}
        label={`${summary.upToDate} of ${summary.total} logs up to date`}
      />
      {summary.errors > 0 && (
        <Chip
          size="small"
          color="error"
          label={`${summary.errors} with an error, see What To Do`}
        />
      )}
      {summary.delayed > 0 && (
        <Chip
          size="small"
          color="warning"
          variant="outlined"
          label={`${summary.delayed} delayed`}
        />
      )}
      {summary.waiting > 0 && (
        <Chip
          size="small"
          variant="outlined"
          label={`${summary.waiting} waiting to start`}
        />
      )}
    </Stack>
  )

  return (
    <CippTablePage
      title="Log Collection"
      tableFilter={tableFilter}
      apiUrl={apiUrl}
      queryKey={`AuditLogCollection-${tenant}`}
      simpleColumns={simpleColumns}
      offCanvas={auditLogFeedOffCanvas}
      filters={auditLogFeedFilters}
    />
  )
}

Page.getLayout = (page) => (
  <DashboardLayout>
    <TabbedLayout tabOptions={tabOptions}>{page}</TabbedLayout>
  </DashboardLayout>
)

export default Page

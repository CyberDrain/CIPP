import React from 'react'
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import router from 'next/router'
import { renderWithProviders } from '../test-utils'
import { api, getResult } from '../mocks/api-call'

vi.mock('../../src/api/ApiCall', async () =>
  (await import('../mocks/api-call')).apiCallMock()
)
const table = vi.hoisted(() => ({
  props: null,
  dataTable: null,
  dataTables: [],
}))
vi.mock('../../src/components/CippComponents/CippTablePage.jsx', () => ({
  CippTablePage: (props) => {
    table.props = props
    return <div>{props.tableFilter}</div>
  },
}))
vi.mock('../../src/components/CippTable/CippDataTable', () => ({
  CippDataTable: (props) => {
    table.dataTable = props
    table.dataTables.push(props)
    return null
  },
}))

import RunsPage from '../../src/pages/cloud-backup/runs/index.jsx'
import OverviewPage from '../../src/pages/cloud-backup/overview/index.jsx'

const policies = getResult({
  data: [
    { Id: 'pol-1', Name: 'Nightly config' },
    { Id: 'pol-2', Name: 'Hourly CA' },
  ],
})
const emptyGet = getResult()

beforeEach(() => {
  vi.clearAllMocks()
  api.get = (opts) =>
    opts.url === '/api/ListCloudBackupPolicies' ? policies : emptyGet
})

afterEach(() => {
  router.query = {}
})

describe('Cloud Backup runs', () => {
  it('lists the runs of every policy for the selected tenant by default', () => {
    renderWithProviders(<RunsPage />)

    expect(table.props.apiUrl).toBe('/api/ListCloudBackupRuns')
    expect(table.props.apiData).toEqual({
      PolicyId: undefined,
      InvalidateCIPPCache: true,
    })
    expect(table.props.queryKey).toBe('ListCloudBackupRuns-testdomain.com-all')
    expect(table.props.simpleColumns).toContain('CloudBackupStatus')
    expect(table.props.simpleColumns).toContain('CloudBackupSize')
    expect(
      table.props.dataMap({
        Id: 'run-1',
        Status: 'Succeeded',
        StartedAt: '2026-11-19T02:00:00Z',
        Bytes: 10,
      })
    ).toMatchObject({
      Id: 'run-1',
      Status: 'Succeeded',
      CloudBackupStatus: 'Succeeded',
      CloudBackupStartedAt: '2026-11-19T02:00:00Z',
      CloudBackupSize: 10,
    })
  })

  it('filters to the policy picked above the table', async () => {
    const user = userEvent.setup()
    renderWithProviders(<RunsPage />)

    await user.click(
      screen.getByRole('combobox', { name: 'Show runs for policy' })
    )
    await user.click(await screen.findByRole('option', { name: 'Hourly CA' }))

    await waitFor(() => expect(table.props.apiData.PolicyId).toBe('pol-2'))
    expect(table.props.queryKey).toBe(
      'ListCloudBackupRuns-testdomain.com-pol-2'
    )
  })

  it('opens filtered when linked from a policy', async () => {
    router.query = { PolicyId: 'pol-1' }
    renderWithProviders(<RunsPage />)

    await waitFor(() => expect(table.props.apiData.PolicyId).toBe('pol-1'))
  })

  it('shows the run and the result for each mailbox', () => {
    const owners = getResult({
      data: [
        {
          OwnerId: 'u-1',
          DisplayName: 'Adele Vance',
          Items: 1200,
          Bytes: 10240,
          Deleted: 3,
          Status: 'Succeeded',
          Warnings: [],
        },
        {
          OwnerId: 'u-2',
          Items: 0,
          Bytes: 0,
          Status: 'Failed',
          Warnings: '["Mailbox not found"]',
        },
      ],
    })
    api.get = (opts) =>
      opts.url === '/api/ListCloudBackupRunOwners' ? owners : emptyGet
    renderWithProviders(<RunsPage />)
    renderWithProviders(
      table.props.offCanvas.children({
        Id: 'pol-1_0001',
        PolicyName: 'Mail and files',
        Tenant: 'contoso.com',
        Workload: 'exchange',
        Status: 'PartialSuccess',
        StartedAt: '2026-11-19T02:00:00Z',
        CompletedAt: '2026-11-19T03:05:00Z',
        DurationSeconds: 3900,
        Owners: 40,
        OwnersFailed: 1,
        Items: 412,
        Bytes: 2621440,
        Warnings: ['1 mailbox could not be read'],
      })
    )

    expect(
      screen.getByText('Exchange Online backup of contoso.com')
    ).toBeInTheDocument()
    expect(screen.getByText('Partial success')).toBeInTheDocument()
    expect(screen.getByText('2.5 MB')).toBeInTheDocument()
    expect(screen.getByText('1 h 5 min')).toBeInTheDocument()
    expect(screen.getByText('40 (1 failed)')).toBeInTheDocument()
    expect(screen.getByText('1 mailbox could not be read')).toBeInTheDocument()

    expect(table.dataTable.title).toBe('Mailboxes in this run')
    expect(table.dataTable.simpleColumns).toEqual([
      'CloudBackupSource',
      'CloudBackupStatus',
      'Items',
      'CloudBackupSize',
      'CloudBackupDeleted',
      'CloudBackupWarnings',
    ])
    expect(table.dataTable.data).toEqual([
      expect.objectContaining({
        CloudBackupSource: 'Adele Vance',
        CloudBackupStatus: 'Succeeded',
        CloudBackupSize: 10240,
        CloudBackupDeleted: 3,
        CloudBackupWarnings: '',
      }),
      expect.objectContaining({
        CloudBackupSource: 'u-2',
        CloudBackupStatus: 'Failed',
        CloudBackupDeleted: 0,
        CloudBackupWarnings: 'Mailbox not found',
      }),
    ])
  })

  it('reads the per-source results of the run that was opened', async () => {
    const { ApiGetCall } = await import('../../src/api/ApiCall')
    renderWithProviders(<RunsPage />)
    renderWithProviders(
      table.props.offCanvas.children({
        Id: 'pol-1_0002',
        Tenant: 'contoso.com',
        Workload: 'sharepoint',
        Status: 'Running',
      })
    )

    expect(ApiGetCall).toHaveBeenCalledWith(
      expect.objectContaining({
        url: '/api/ListCloudBackupRunOwners',
        data: { RunId: 'pol-1_0002' },
        queryKey: 'ListCloudBackupRunOwners-pol-1_0002',
      })
    )
    expect(table.dataTable.title).toBe('Sites in this run')
  })

  it('shows the service and the number of sources in the table', () => {
    renderWithProviders(<RunsPage />)

    expect(table.props.simpleColumns).toContain('CloudBackupWorkload')
    expect(table.props.simpleColumns).toContain('CloudBackupSources')
    expect(table.props.actions).toBeUndefined()
    expect(
      table.props.dataMap({ Workload: 'onedrive', OwnerCount: 12 })
    ).toMatchObject({ CloudBackupWorkload: 'OneDrive', CloudBackupSources: 12 })
  })

  it('reports a run that is still going', () => {
    renderWithProviders(<RunsPage />)
    expect(
      table.props.dataMap({ Status: 'Running', DurationSeconds: null }).Duration
    ).toBe('Still running')
  })
})

describe('Cloud Backup overview', () => {
  const overview = (data) => {
    const result = getResult({ data })
    api.get = () => result
  }

  it('shows the totals and the latest run per tenant', () => {
    const latestRuns = [
      {
        PolicyId: 'pol-1',
        PolicyName: 'Nightly config',
        Tenant: 'contoso.com',
        Status: 'Succeeded',
        CompletedAt: '2026-11-19T02:03:05Z',
        Items: 412,
        Bytes: 2621440,
      },
    ]
    overview({
      Policies: 3,
      EnabledPolicies: 2,
      Destinations: 1,
      TenantsCovered: 41,
      Failures24h: 0,
      LatestBytes: 1073741824,
      LatestRuns: latestRuns,
    })
    renderWithProviders(<OverviewPage />)

    expect(screen.getByText('41')).toBeInTheDocument()
    expect(screen.getByText('1.0 GB')).toBeInTheDocument()
    expect(table.dataTable.data).toEqual([
      {
        ...latestRuns[0],
        CloudBackupWorkload: undefined,
        CloudBackupStatus: 'Succeeded',
        CloudBackupStartedAt: undefined,
        CloudBackupCompletedAt: '2026-11-19T02:03:05Z',
        CloudBackupSize: 2621440,
      },
    ])
    expect(
      screen.queryByText(/Start by adding a destination/)
    ).not.toBeInTheDocument()
  })

  it('shows the totals for each service', () => {
    overview({
      Policies: 1,
      Destinations: 1,
      LatestRuns: [],
      Workloads: [
        {
          Workload: 'teams',
          Owners: 12,
          Items: 900,
          Bytes: 1024,
          Failures24h: 1,
        },
        { Workload: 'exchange', Owners: 40, Items: 50000, Bytes: 4096 },
      ],
    })
    table.dataTables = []
    renderWithProviders(<OverviewPage />)

    const byService = table.dataTables.find(
      (props) => props.title === 'By service'
    )
    expect(byService.data).toEqual([
      expect.objectContaining({
        CloudBackupWorkload: 'Exchange Online',
        CloudBackupSources: 40,
        CloudBackupSize: 4096,
        CloudBackupFailures24h: 0,
      }),
      expect.objectContaining({
        CloudBackupWorkload: 'Teams',
        CloudBackupSources: 12,
        CloudBackupFailures24h: 1,
      }),
    ])
  })

  it('reads per-service totals keyed by service too', () => {
    overview({
      Policies: 1,
      Destinations: 1,
      LatestRuns: [],
      Workloads: '{"OneDrive":{"Owners":3,"Bytes":10}}',
    })
    table.dataTables = []
    renderWithProviders(<OverviewPage />)

    const byService = table.dataTables.find(
      (props) => props.title === 'By service'
    )
    expect(byService.data).toEqual([
      expect.objectContaining({
        Workload: 'onedrive',
        CloudBackupWorkload: 'OneDrive',
        CloudBackupSources: 3,
      }),
    ])
  })

  it('points a new install at adding a destination', () => {
    overview({
      Policies: 0,
      EnabledPolicies: 0,
      Destinations: 0,
      LatestRuns: [],
    })
    renderWithProviders(<OverviewPage />)

    expect(
      screen.getByText(/Start by adding a destination/)
    ).toBeInTheDocument()
    expect(
      screen.getByRole('link', { name: 'Add destination' })
    ).toHaveAttribute('href', '/cloud-backup/destinations/add')
  })

  it('points at adding a policy once a destination exists', () => {
    overview({
      Policies: 0,
      EnabledPolicies: 0,
      Destinations: 1,
      LatestRuns: [],
    })
    renderWithProviders(<OverviewPage />)

    expect(screen.getByRole('link', { name: 'Add policy' })).toHaveAttribute(
      'href',
      '/cloud-backup/policies/add'
    )
  })
})

import React from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { act, fireEvent, screen } from '@testing-library/react'
import { renderWithProviders, settingsWith } from '../test-utils'
import { SettingsContext } from '../../src/contexts/settings-context'
import { api, getResult } from '../mocks/api-call'

const captured = vi.hoisted(() => ({
  tables: [],
  dialogs: [],
  largeFiles: null,
  readiness: null,
  trackers: {},
  refresh: null,
}))

vi.mock('../../src/api/ApiCall', async () =>
  (await import('../mocks/api-call')).apiCallMock()
)
vi.mock('../../src/hooks/use-permissions', () => ({
  usePermissions: () => ({ checkPermissions: () => true }),
}))
vi.mock('../../src/components/CippTable/CippDataTable', () => ({
  CippDataTable: (props) => {
    captured.tables.push(props)
    return null
  },
}))
vi.mock('../../src/components/CippCards/CippChartCard', () => ({
  CippChartCard: () => null,
}))
vi.mock('../../src/components/CippCards/CippSharePointQuotaCard', () => ({
  CippSharePointQuotaCard: () => null,
}))
vi.mock('../../src/components/CippComponents/CippMultiQueueTracker', () => ({
  CippMultiQueueTracker: (props) => {
    captured.trackers[props.label] = props
    return null
  },
}))
vi.mock('../../src/components/CippComponents/CippQueryRefreshButton', () => ({
  CippQueryRefreshButton: (props) => {
    captured.refresh = props
    return null
  },
}))
vi.mock('../../src/components/CippComponents/CippApiDialog', () => ({
  CippApiDialog: (props) => {
    captured.dialogs.push(props)
    return null
  },
}))
vi.mock('../../src/components/CippComponents/CippStorageCleanupDrawer', () => ({
  CippStorageCleanupDrawer: () => null,
}))
vi.mock('../../src/components/CippPdf/StorageReportButton', () => ({
  StorageReportButton: () => null,
}))
vi.mock('../../src/components/CippComponents/CippSharePointLargeFiles', () => ({
  CippSharePointLargeFiles: (props) => {
    captured.largeFiles = props
    return null
  },
}))
vi.mock(
  '../../src/components/CippComponents/CippSharePointArchiveReadiness',
  () => ({
    CippSharePointArchiveReadiness: (props) => {
      captured.readiness = props
      return null
    },
  })
)

import Page from '../../src/pages/teams-share/reports/storage-report/index.jsx'

const GB = 1024 ** 3
const siteResult = getResult({
  data: [
    {
      siteId: 'contoso.sharepoint.com,1,2',
      webUrl: 'https://contoso.sharepoint.com/sites/projects',
      displayName: 'Projects',
      storageUsedInGigabytes: 300,
      storageUsedInBytes: 300 * GB,
      rootWebTemplate: 'Group',
    },
  ],
})
const oneDriveResult = getResult({
  data: [
    {
      webUrl: 'https://contoso-my.sharepoint.com/personal/megan',
      displayName: 'Megan Bowen',
      storageUsedInGigabytes: 700,
    },
  ],
})
const settingsMissing = getResult({
  isError: true,
  isSuccess: false,
  error: {
    response: {
      status: 404,
      data: { Results: 'No SharePoint configuration is stored.' },
    },
  },
})
const emptyResult = getResult({ data: [] })

const route = (quotaResult) => (opts) => {
  if (opts.url?.includes('type=SharePointSiteUsage')) return siteResult
  if (opts.url?.includes('type=OneDriveUsageAccount')) return oneDriveResult
  if (opts.url === '/api/ListSharepointQuota') return quotaResult
  if (opts.url === '/api/ListSharePointArchiveSettings') return settingsMissing
  return emptyResult
}

const siteAction = (label) => {
  const table = captured.tables.findLast(
    (props) => props.title === 'SharePoint Sites'
  )
  return table.actions.find((action) => action.label === label)
}

const openLargeFiles = () =>
  fireEvent.click(screen.getByRole('tab', { name: /Large files/ }))

const startScan = (result) => {
  const scan = captured.dialogs.findLast(
    (props) => props.title === 'Scan large files'
  )
  act(() => scan.api.onSuccess(result))
}

const largeFilesRequest = () =>
  api.calls.findLast((opts) => opts.url === '/api/ListStorageLargeFiles')

// Lets a test switch the selected tenant without losing the page's state.
const TenantSwitcher = () => {
  const [tenant, setTenant] = React.useState('contoso.onmicrosoft.com')
  return (
    <SettingsContext.Provider value={settingsWith({ currentTenant: tenant })}>
      <button onClick={() => setTenant('fabrikam.onmicrosoft.com')}>
        Switch tenant
      </button>
      <button onClick={() => setTenant('contoso.onmicrosoft.com')}>
        Back to contoso
      </button>
      <Page />
    </SettingsContext.Provider>
  )
}

describe('Storage Report page: archive actions', () => {
  beforeEach(() => {
    captured.tables = []
    captured.dialogs = []
    captured.largeFiles = null
    captured.readiness = null
    captured.trackers = {}
    captured.refresh = null
    api.calls = []
    const routed = route(getResult({ data: {} }))
    api.get = (opts) => {
      api.calls.push(opts)
      return routed(opts)
    }
  })

  it('archives a whole site one at a time', () => {
    renderWithProviders(<Page />)

    expect(siteAction('Archive site…').hideBulk).toBe(true)
  })

  const withSiteArchiveStatus = (archiveStatus) => {
    const site = { ...siteResult.data[0] }
    if (archiveStatus !== undefined) site.archiveStatus = archiveStatus
    const routed = route(getResult({ data: {} }))
    api.get = (opts) =>
      opts.url?.includes('type=SharePointSiteUsage')
        ? getResult({ data: [site] })
        : routed(opts)
  }

  const sitesTable = () =>
    captured.tables.findLast((props) => props.title === 'SharePoint Sites')

  it.each([
    ['active', true, false],
    ['archived', false, true],
    ['reactivating', false, false],
    ['unknown', true, true],
    [undefined, true, true],
  ])(
    'for a site whose archive state is %s offers Archive site %s and Reactivate site %s',
    (archiveStatus, canArchive, canReactivate) => {
      withSiteArchiveStatus(archiveStatus)
      renderWithProviders(<Page />)
      const row = sitesTable().data[0]

      expect(row.archiveStatus).toBe(archiveStatus)
      expect(siteAction('Archive site…').condition(row)).toBe(canArchive)
      expect(siteAction('Reactivate site…').condition(row)).toBe(canReactivate)
      expect(siteAction('Archive site…').condition([row])).toBe(canArchive)
    }
  )

  it('shows the site archive state only when the sites carry one', () => {
    withSiteArchiveStatus('archived')
    renderWithProviders(<Page />)
    expect(sitesTable().simpleColumns).toContain('archiveStatus')

    withSiteArchiveStatus(undefined)
    renderWithProviders(<Page />)
    expect(sitesTable().simpleColumns).not.toContain('archiveStatus')
  })

  it('keeps the site archive confirmation texts', () => {
    renderWithProviders(<Page />)

    expect(siteAction('Archive site…').confirmText).toMatch(
      /^Archive the whole site \[displayName\]\?/
    )
    expect(siteAction('Reactivate site…').confirmText).toMatch(
      /^Reactivate the archived site \[displayName\]\?/
    )
  })

  it('says the file archiving switch shows the new setting only after the next usage sync', () => {
    renderWithProviders(<Page />)

    expect(siteAction('File archiving…').confirmText).toContain(
      'until the next Sync usage'
    )
  })

  it('passes a missing settings error to the banner', () => {
    renderWithProviders(<Page />)

    expect(captured.readiness.settings).toBeNull()
    expect(captured.readiness.error.response.status).toBe(404)
  })

  it('does not treat the usage report totals, which include OneDrive, as the SharePoint pool', () => {
    renderWithProviders(<Page />)
    openLargeFiles()

    expect(captured.largeFiles.activeBytes).toBeUndefined()
  })

  it('uses the stored SharePoint pool usage when it is available', () => {
    api.get = route(getResult({ data: { GeoUsedStorageMB: 2048 } }))
    renderWithProviders(<Page />)
    openLargeFiles()

    expect(captured.largeFiles.activeBytes).toBe(2 * GB)
  })

  it('keeps edited prices when the technician switches tab and comes back', () => {
    renderWithProviders(<Page />)
    openLargeFiles()
    act(() =>
      captured.largeFiles.onPricesChange({
        archiveRate: '0.03',
        storageRate: 0.16,
      })
    )

    fireEvent.click(screen.getByRole('tab', { name: /SharePoint Sites/ }))
    openLargeFiles()

    expect(captured.largeFiles.prices).toEqual({
      archiveRate: '0.03',
      storageRate: 0.16,
    })
  })

  it('does not say a scan is running before one is queued', () => {
    renderWithProviders(<Page />)
    openLargeFiles()

    expect(captured.largeFiles.scan).toBeNull()
    expect(captured.trackers['Large file scan'].queueIds).toEqual([])
  })

  it('tells the Large files tab the newest file listed when the scan was queued', () => {
    const routed = route(getResult({ data: {} }))
    api.get = (opts) => {
      api.calls.push(opts)
      return opts.url === '/api/ListStorageLargeFiles'
        ? getResult({
            data: [
              { id: 'a', collectedAt: '2026-11-20T09:00:00Z' },
              { id: 'b', collectedAt: '2026-11-21T09:00:00Z' },
            ],
          })
        : routed(opts)
    }
    renderWithProviders(<Page />)
    startScan({ Metadata: { QueueId: 'queue-1' } })
    openLargeFiles()

    expect(captured.largeFiles.scan).toEqual({
      listedAt: Date.parse('2026-11-21T09:00:00Z'),
      queueId: 'queue-1',
    })
    expect(captured.trackers['Large file scan'].queueIds).toEqual(['queue-1'])
    expect(largeFilesRequest().data.InvalidateCIPPCache).toBe(true)
  })

  const alreadyRunning = {
    Results:
      'A StorageLargeFiles cache operation is already running on tenant testdomain.com, so this request was skipped',
    Metadata: {
      InstanceId: 'CIPPDBCache_StorageLargeFiles_testdomain.com-Skipped',
      QueueId: null,
    },
  }

  it('records a scan that was already running as one with nothing to track', () => {
    renderWithProviders(<Page />)
    startScan(alreadyRunning)
    openLargeFiles()

    expect(captured.largeFiles.scan).toEqual({
      listedAt: 0,
      queueId: null,
    })
    expect(captured.trackers['Large file scan'].queueIds).toEqual([])
  })

  it('keeps tracking the scan it started when asked to start another', () => {
    renderWithProviders(<Page />)
    startScan({ Metadata: { QueueId: 'queue-1' } })
    startScan(alreadyRunning)
    openLargeFiles()

    expect(captured.largeFiles.scan.queueId).toBe('queue-1')
    expect(captured.trackers['Large file scan'].queueIds).toEqual(['queue-1'])
  })

  it.each(['Completed', 'Failed', 'Completed (with errors)'])(
    'records the end state %s the queue reported and when it ended',
    (status) => {
      renderWithProviders(<Page />)
      startScan({ Metadata: { QueueId: 'queue-1' } })
      openLargeFiles()
      expect(captured.largeFiles.scan.endState).toBeUndefined()

      const before = Date.now()
      act(() =>
        captured.trackers['Large file scan'].onFinished(status, 'queue-1')
      )

      expect(captured.largeFiles.scan.endState).toBe(status)
      expect(captured.largeFiles.scan.endedAt).toBeGreaterThanOrEqual(before)
    }
  )

  it('ignores the end of an earlier run', () => {
    renderWithProviders(<Page />)
    startScan({ Metadata: { QueueId: 'queue-2' } })
    openLargeFiles()

    act(() =>
      captured.trackers['Large file scan'].onFinished('Completed', 'queue-1')
    )

    expect(captured.largeFiles.scan.endState).toBeUndefined()
  })

  it('keeps a scan to the tenant it was started for', () => {
    renderWithProviders(<TenantSwitcher />)
    startScan({ Metadata: { QueueId: 'queue-1' } })
    openLargeFiles()
    expect(captured.largeFiles.scan.queueId).toBe('queue-1')

    fireEvent.click(screen.getByRole('button', { name: 'Switch tenant' }))

    expect(captured.largeFiles.scan).toBeNull()
    expect(captured.trackers['Large file scan'].queueIds).toEqual([])
    expect(largeFilesRequest().data.InvalidateCIPPCache).toBeUndefined()

    fireEvent.click(screen.getByRole('button', { name: 'Back to contoso' }))

    expect(captured.largeFiles.scan.queueId).toBe('queue-1')
  })

  it("keeps the first tenant's scan when a scan is started for a second tenant", () => {
    renderWithProviders(<TenantSwitcher />)
    startScan({ Metadata: { QueueId: 'queue-1' } })
    fireEvent.click(screen.getByRole('button', { name: 'Switch tenant' }))
    startScan({ Metadata: { QueueId: 'queue-2' } })
    openLargeFiles()
    expect(captured.trackers['Large file scan'].queueIds).toEqual(['queue-2'])

    fireEvent.click(screen.getByRole('button', { name: 'Back to contoso' }))

    expect(captured.largeFiles.scan.queueId).toBe('queue-1')
    expect(captured.trackers['Large file scan'].queueIds).toEqual(['queue-1'])
    act(() =>
      captured.trackers['Large file scan'].onFinished('Completed', 'queue-1')
    )
    expect(captured.largeFiles.scan.endState).toBe('Completed')
  })

  it('records the end of a scan once when the tracker reports it again', () => {
    renderWithProviders(<TenantSwitcher />)
    startScan({ Metadata: { QueueId: 'queue-1' } })
    openLargeFiles()
    act(() =>
      captured.trackers['Large file scan'].onFinished('Completed', 'queue-1')
    )
    const first = captured.largeFiles.scan

    fireEvent.click(screen.getByRole('button', { name: 'Switch tenant' }))
    fireEvent.click(screen.getByRole('button', { name: 'Back to contoso' }))
    act(() =>
      captured.trackers['Large file scan'].onFinished(
        'Completed (with errors)',
        'queue-1'
      )
    )

    expect(captured.largeFiles.scan).toBe(first)
  })

  it('reloads the large files, archive settings and quota with everything else on Refresh', () => {
    renderWithProviders(<Page />)

    expect(captured.refresh.queryKeys).toEqual(
      expect.arrayContaining([
        'ListStorageLargeFiles-testdomain.com',
        'ListSharePointArchiveSettings-testdomain.com',
        'testdomain.com-ListSharepointQuota',
        'ListStorageCleanupScan-testdomain.com',
        'StorageReport-SharePointSiteUsage-testdomain.com',
      ])
    )
  })

  it('gives the libraries listed under a site the site address for the archive rule', () => {
    renderWithProviders(<Page />)
    const sites = captured.tables.findLast(
      (props) => props.title === 'SharePoint Sites'
    )
    const libraries = sites.subTables.find((sub) => sub.id === 'libraries')

    expect(
      libraries.table.dataMap(
        {
          id: 'list-1',
          displayName: 'Site Assets',
          template: 'documentLibrary',
        },
        { parentRow: siteResult.data[0] }
      ).siteUrl
    ).toBe('https://contoso.sharepoint.com/sites/projects')
  })
})

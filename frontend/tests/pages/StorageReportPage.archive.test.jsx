import { describe, it, expect, vi, beforeEach } from 'vitest'
import { renderWithProviders } from '../test-utils'
import { api, getResult } from '../mocks/api-call'

const captured = vi.hoisted(() => ({
  tables: [],
  dialogs: [],
  readiness: null,
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

describe('Storage Report page: archive actions', () => {
  beforeEach(() => {
    captured.tables = []
    captured.dialogs = []
    captured.readiness = null
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

  it('reloads the archive settings with everything else on Refresh', () => {
    renderWithProviders(<Page />)

    expect(captured.refresh.queryKeys).toEqual(
      expect.arrayContaining([
        'ListSharePointArchiveSettings-testdomain.com',
        'ListStorageCleanupScan-testdomain.com',
        'StorageReport-SharePointSiteUsage-testdomain.com',
      ])
    )
  })
})

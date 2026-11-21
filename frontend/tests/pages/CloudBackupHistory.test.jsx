import React from 'react'
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithProviders } from '../test-utils'
import { api, getResult } from '../mocks/api-call'

vi.mock('../../src/api/ApiCall', async () =>
  (await import('../mocks/api-call')).apiCallMock()
)
const ui = vi.hoisted(() => ({ page: null, tables: {} }))
vi.mock('../../src/components/CippComponents/CippTablePage.jsx', () => ({
  CippTablePage: (props) => {
    ui.page = props
    return null
  },
}))
vi.mock('../../src/components/CippTable/CippDataTable', () => ({
  CippDataTable: (props) => {
    ui.tables[props.title] = props
    return null
  },
}))
vi.mock('../../src/utils/cippVersion', () => ({
  buildVersionedHeaders: async () => ({}),
}))

import HistoryPage from '../../src/pages/cloud-backup/history/index.jsx'

const restoreJob = {
  Id: 'job-2',
  Type: 'Restore',
  Status: 'Completed',
  Workload: 'exchange',
  SourceOwner: 'Adele Vance',
  TargetOwner: 'megan@contoso.com',
  RequestedBy: 'tech@msp.com',
  CreatedAt: '2026-11-19T10:00:00Z',
  CompletedAt: '2026-11-19T10:05:00Z',
  Parameters: '{"Location":"RestoredFolder","ConflictAction":"Copy"}',
  Summary: { Succeeded: 4, Failed: 1 },
  Result: {
    Total: 500,
    Items: [
      {
        Key: 'items/A.fts',
        Name: 'Quarterly report',
        Path: 'Inbox',
        Type: 'message',
        Action: 'Copy',
        Status: 'Failed',
        Message: 'Mailbox is full',
        TargetPath: 'Restored 2026-11-19 10:00/Inbox',
      },
    ],
  },
}
const exportJob = {
  Id: 'job-9',
  Type: 'Export',
  Status: 'Completed',
  Workload: 'teams',
  OwnerId: 'team-1',
  Summary: { Items: 30 },
  DownloadAvailable: true,
  ExpiresAt: '2099-01-01T00:00:00Z',
}

let me
let jobs
let saved

beforeEach(() => {
  vi.clearAllMocks()
  ui.tables = {}
  jobs = {}
  saved = []
  me = getResult({
    data: {
      clientPrincipal: { userRoles: ['admin'] },
      permissions: [
        'CIPP.CloudBackup.Read',
        'CIPP.CloudBackupRestore.ReadWrite',
      ],
    },
  })
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(
    function () {
      saved.push(this.download)
    }
  )
  URL.createObjectURL = vi.fn(() => 'blob:x')
  URL.revokeObjectURL = vi.fn()
  api.get = (opts) => {
    if (opts.url === '/api/me') return me
    if (opts.url === '/api/ListCloudBackupJobs')
      return jobs[opts.data?.Id] ?? getResult()
    return getResult()
  }
})

afterEach(() => {
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe('Cloud Backup restore history', () => {
  it('lists only restores, previews and exports of the selected tenant', () => {
    renderWithProviders(<HistoryPage />)

    expect(ui.page.apiUrl).toBe('/api/ListCloudBackupJobs')
    expect(ui.page.queryKey).toBe('ListCloudBackupJobs-history-testdomain.com')
    expect(ui.page.apiData).toEqual({ InvalidateCIPPCache: true })
    expect(ui.page.offCanvasOnRowClick).toBe(true)
    expect(ui.page.offCanvas.title).toBe('Restore or Export Details')
    for (const type of ['Restore', 'RestorePreview', 'Export']) {
      expect(ui.page.dataFilter({ Type: type })).toBe(true)
    }
    for (const type of ['Compare', 'Provision']) {
      expect(ui.page.dataFilter({ Type: type })).toBe(false)
    }
    expect(ui.page.dataMap(restoreJob)).toMatchObject({
      CloudBackupJobType: 'Restore',
      CloudBackupStatus: 'Completed',
      CloudBackupWorkload: 'Exchange Online',
      CloudBackupOwner: 'Adele Vance',
      CloudBackupTarget: 'megan@contoso.com',
      CloudBackupRequestedBy: 'tech@msp.com',
      CloudBackupJobSummary: '4 restored, 1 failed',
    })
    expect(ui.page.dataMap(exportJob)).toMatchObject({
      CloudBackupJobType: 'Export',
      CloudBackupOwner: 'team-1',
      CloudBackupTarget: 'Download',
      CloudBackupJobSummary: '30 items exported',
    })
  })

  it('shows a restore with its options and per-item results', () => {
    jobs['job-2'] = getResult({ data: restoreJob })
    renderWithProviders(<HistoryPage />)
    renderWithProviders(ui.page.offCanvas.children(ui.page.dataMap(restoreJob)))

    expect(screen.getByText('Restore of Adele Vance')).toBeInTheDocument()
    expect(screen.getByText(/Keep both: restore a copy/)).toBeInTheDocument()
    expect(
      screen.getByText(/A new folder named "Restored"/)
    ).toBeInTheDocument()
    expect(
      screen.getByText('Showing the first 1 of 500 items.')
    ).toBeInTheDocument()
    const results = ui.tables['Restore results']
    expect(results.data[0]).toMatchObject({
      CloudBackupItemName: 'Quarterly report',
      CloudBackupRestoreAction: 'Restore as a copy',
      CloudBackupStatus: 'Failed',
      CloudBackupMessage: 'Mailbox is full',
    })
    expect(results.simpleColumns).toContain('CloudBackupStatus')
  })

  it('polls a running job', async () => {
    const { ApiGetCall } = await import('../../src/api/ApiCall')
    jobs['job-2'] = getResult({ data: { ...restoreJob, Status: 'Running' } })
    renderWithProviders(<HistoryPage />)
    renderWithProviders(ui.page.offCanvas.children(ui.page.dataMap(restoreJob)))

    expect(screen.getByText(/still running/)).toBeInTheDocument()
    const call = ApiGetCall.mock.calls
      .map(([opts]) => opts)
      .find((opts) => opts.data?.Id === 'job-2')
    expect(
      call.refetchInterval({ state: { data: { Status: 'Running' } } })
    ).toBe(3000)
  })

  it('downloads an export until it expires', async () => {
    const user = userEvent.setup()
    const fetchMock = vi.fn(async () => ({
      ok: true,
      status: 200,
      headers: {
        get: () => "attachment; filename*=UTF-8''Team%20export.zip",
      },
      blob: async () => new Blob(['zip']),
    }))
    vi.stubGlobal('fetch', fetchMock)
    jobs['job-9'] = getResult({ data: exportJob })
    renderWithProviders(<HistoryPage />)
    renderWithProviders(ui.page.offCanvas.children(ui.page.dataMap(exportJob)))

    await user.click(screen.getByRole('button', { name: 'Download export' }))
    await waitFor(() => expect(saved).toEqual(['Team export.zip']))
    expect(fetchMock.mock.calls[0][0]).toBe(
      '/api/ExecCloudBackupDownload?JobId=job-9&Part=0'
    )
  })

  it('says when an export has expired', () => {
    const expired = { ...exportJob, ExpiresAt: '2020-01-01T00:00:00Z' }
    jobs['job-9'] = getResult({ data: expired })
    renderWithProviders(<HistoryPage />)
    renderWithProviders(ui.page.offCanvas.children(ui.page.dataMap(expired)))

    expect(screen.getByText(/This export has expired/)).toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: 'Download export' })
    ).not.toBeInTheDocument()
  })

  it('hides export downloads without the restore permission', () => {
    me = getResult({
      data: {
        clientPrincipal: { userRoles: ['readonly'] },
        permissions: ['CIPP.CloudBackup.Read'],
      },
    })
    jobs['job-9'] = getResult({ data: exportJob })
    renderWithProviders(<HistoryPage />)
    renderWithProviders(ui.page.offCanvas.children(ui.page.dataMap(exportJob)))

    expect(
      screen.queryByRole('button', { name: 'Download export' })
    ).not.toBeInTheDocument()
    expect(
      screen.getByText(/Downloading exports needs the Cloud Backup restore/)
    ).toBeInTheDocument()
  })
})

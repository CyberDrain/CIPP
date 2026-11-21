import React from 'react'
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { act, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { LocalizationProvider } from '@mui/x-date-pickers/LocalizationProvider'
import { AdapterDateFns } from '@mui/x-date-pickers/AdapterDateFns'
import { renderWithProviders, settingsWith } from '../test-utils'
import { api, getResult, postResult } from '../mocks/api-call'
import { ApiGetCall } from '../../src/api/ApiCall'

vi.mock('../../src/api/ApiCall', async () =>
  (await import('../mocks/api-call')).apiCallMock()
)
const ui = vi.hoisted(() => ({ tables: {}, dialogs: {} }))
vi.mock('../../src/components/CippTable/CippDataTable', () => ({
  CippDataTable: (props) => {
    ui.tables[props.title] = props
    return <div data-testid={`table-${props.title}`} />
  },
}))
vi.mock('../../src/components/CippComponents/CippApiDialog', () => ({
  CippApiDialog: (props) => {
    ui.dialogs[props.title] = props
    return props.createDialog.open ? (
      <div role="dialog">
        <h2>{props.title}</h2>
        {props.api.confirmText}
      </div>
    ) : null
  },
}))
vi.mock('../../src/utils/cippVersion', () => ({
  buildVersionedHeaders: async () => ({ 'X-CIPP-Version': 'test' }),
}))

import RestorePage from '../../src/pages/cloud-backup/restore/index.jsx'

const policy = {
  Id: 'pol-1',
  Name: 'Mail and files',
  Workloads: ['exchange', 'onedrive', 'teams'],
  Tenants: [
    {
      label: 'Contoso (contoso.com)',
      value: 'contoso.com',
      type: 'Tenant',
      addedFields: {
        customerId: 'cid-contoso',
        defaultDomainName: 'contoso.com',
      },
    },
  ],
}
const owners = [
  {
    OwnerId: 'u-adele',
    DisplayName: 'Adele Vance',
    UserPrincipalName: 'adele@contoso.com',
    Removed: false,
  },
  {
    OwnerId: 'u-leaver',
    DisplayName: 'Lee Gu',
    UserPrincipalName: 'lee@contoso.com',
    Removed: true,
    RemovedReason: 'Removed',
    RemovedAt: '2026-11-01T00:00:00Z',
  },
]
const listing = {
  RunStamp: '20261119T020000Z',
  Total: 250,
  Items: [
    {
      Key: 'items/AAA.fts',
      Path: 'Inbox',
      Name: 'Quarterly report',
      Type: 'message',
      Size: 2048,
      Modified: '2026-11-18T10:00:00Z',
      VersionId: 'v-1',
      Extra: '{"from":"megan@contoso.com","to":"adele@contoso.com"}',
    },
    { Key: 'folders/inbox/', Path: '', Name: 'Inbox', Type: 'folder' },
  ],
  Folders: [{ Key: 'folders/sub/', Path: 'Projects', Name: 'Projects' }],
}
const completedPreview = {
  Id: 'job-1',
  Type: 'RestorePreview',
  Status: 'Completed',
  Summary: { Create: 2, Overwrite: 0, Copy: 0, Skip: 3, NotRestorable: 1 },
  Result: [
    {
      Key: 'items/AAA.fts',
      Name: 'Quarterly report',
      Path: 'Inbox',
      Type: 'message',
      Action: 'Create',
      Status: 'Planned',
    },
  ],
}

const results = {
  policies: getResult({ data: [policy] }),
  owners: getResult({ data: owners }),
  points: getResult({
    data: [
      { RunStamp: '20261119T020000Z', At: '2026-11-19T02:00:00Z' },
      { RunStamp: '20261118T020000Z', At: '2026-11-18T02:00:00Z' },
    ],
  }),
  items: getResult({ data: listing }),
  item: getResult({
    data: {
      ...listing.Items[0],
      Versions: [
        { VersionId: 'v-1', At: '2026-11-18T10:00:00Z', Size: 2048 },
        { VersionId: 'v-0', At: '2026-11-10T10:00:00Z', Size: 1024 },
      ],
    },
  }),
  empty: getResult(),
}
let me
let jobs
let saved

const setPermissions = (permissions) => {
  me = getResult({
    data: { clientPrincipal: { userRoles: ['admin'] }, permissions },
  })
}

beforeEach(() => {
  vi.clearAllMocks()
  ui.tables = {}
  ui.dialogs = {}
  jobs = {}
  setPermissions(['CIPP.CloudBackup.Read', 'CIPP.CloudBackupRestore.ReadWrite'])
  api.post = postResult()
  saved = []
  vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(
    function () {
      saved.push(this.download)
    }
  )
  URL.createObjectURL = vi.fn(() => 'blob:x')
  URL.revokeObjectURL = vi.fn()
  api.get = (opts) => {
    if (!opts.waiting && opts.waiting !== undefined) return results.empty
    if (opts.url === '/api/me') return me
    if (opts.url === '/api/ListCloudBackupPolicies') return results.policies
    if (opts.url === '/api/ListCloudBackupOwners') return results.owners
    if (opts.url === '/api/ListCloudBackupRecoveryPoints') return results.points
    if (opts.url === '/api/ListCloudBackupItems') return results.items
    if (opts.url === '/api/ListCloudBackupItem') return results.item
    if (opts.url === '/api/ListCloudBackupJobs')
      return jobs[opts.data?.Id] ?? results.empty
    return results.empty
  }
})

afterEach(() => {
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

const renderPage = (currentTenant = 'AllTenants') =>
  renderWithProviders(
    <LocalizationProvider dateAdapter={AdapterDateFns}>
      <RestorePage />
    </LocalizationProvider>,
    { settings: settingsWith({ currentTenant }) }
  )

const pick = async (user, label, option) => {
  await user.click(await screen.findByRole('combobox', { name: label }))
  await user.click(await screen.findByRole('option', { name: option }))
}

const lastCall = (url) =>
  ApiGetCall.mock.calls
    .map(([opts]) => opts)
    .filter((opts) => opts.url === url)
    .at(-1)

const openOwner = async (
  user,
  {
    service = 'Exchange Online',
    owner = 'Adele Vance (adele@contoso.com)',
  } = {}
) => {
  renderPage()
  await pick(user, 'Policy', 'Mail and files')
  await pick(user, 'Tenant', 'Contoso (contoso.com)')
  await pick(user, 'Service', service)
  await waitFor(() =>
    expect(screen.getByRole('combobox', { name: /^Backed up/ })).toBeEnabled()
  )
  await user.click(screen.getByRole('combobox', { name: /^Backed up/ }))
  await user.click(await screen.findByRole('option', { name: owner }))
  await waitFor(() => expect(ui.tables['Items in this folder']).toBeDefined())
}

const startPreview = async (user, jobId = 'job-1') => {
  await user.click(screen.getByRole('button', { name: 'Restore' }))
  await user.click(screen.getByRole('button', { name: 'Preview restore' }))
  const [payload, options] = api.post.mutate.mock.calls.at(-1)
  act(() => options.onSuccess({ data: { JobId: jobId } }))
  return payload
}

describe('Cloud Backup browse', () => {
  it('uses the selected tenant instead of asking for one', async () => {
    const user = userEvent.setup()
    renderPage('contoso.com')

    expect(lastCall('/api/ListCloudBackupPolicies')).toMatchObject({
      data: { tenantFilter: 'contoso.com' },
      queryKey: 'ListCloudBackupPolicies-picker-contoso.com',
    })
    await pick(user, 'Policy', 'Mail and files')
    expect(screen.queryByRole('combobox', { name: 'Tenant' })).toBeNull()
    await pick(user, 'Service', 'Exchange Online')

    expect(lastCall('/api/ListCloudBackupOwners').data).toEqual({
      PolicyId: 'pol-1',
      TenantId: 'contoso.com',
      Workload: 'exchange',
    })
  })

  it('lists owners of the picked policy, tenant and service, flagging leavers', async () => {
    const user = userEvent.setup()
    renderPage()
    await pick(user, 'Policy', 'Mail and files')
    await pick(user, 'Tenant', 'Contoso (contoso.com)')
    await pick(user, 'Service', 'Exchange Online')

    expect(lastCall('/api/ListCloudBackupOwners')).toMatchObject({
      data: {
        PolicyId: 'pol-1',
        TenantId: 'cid-contoso',
        Workload: 'exchange',
      },
      waiting: true,
    })
    await user.click(
      screen.getByRole('combobox', { name: 'Backed up mailbox' })
    )
    expect(
      await screen.findByRole('option', {
        name: 'Lee Gu (lee@contoso.com), removed from the tenant',
      })
    ).toBeInTheDocument()
  })

  it('opens the latest point in time and lists the root folder', async () => {
    const user = userEvent.setup()
    await openOwner(user)

    expect(lastCall('/api/ListCloudBackupItems').data).toEqual({
      PolicyId: 'pol-1',
      TenantId: 'cid-contoso',
      Workload: 'exchange',
      OwnerId: 'u-adele',
      AsOf: '20261119T020000Z',
      Path: '',
      Skip: 0,
      Take: 100,
    })
    const table = ui.tables['Items in this folder']
    expect(table.data).toHaveLength(1)
    expect(table.data[0]).toMatchObject({
      CloudBackupItemName: 'Quarterly report',
      CloudBackupItemType: 'Email',
      CloudBackupFrom: 'megan@contoso.com',
    })
    expect(table.simpleColumns).toContain('CloudBackupFrom')
    expect(table.offCanvasOnRowClick).toBe(true)
    expect(screen.getByText('Items 1–100 of 250')).toBeInTheDocument()
  })

  it('opens a folder, pages and goes back to the top', async () => {
    const user = userEvent.setup()
    await openOwner(user)

    await user.click(screen.getByRole('button', { name: 'Projects' }))
    await waitFor(() =>
      expect(lastCall('/api/ListCloudBackupItems').data.Path).toBe('Projects')
    )
    await user.click(screen.getByRole('button', { name: 'Next' }))
    await waitFor(() =>
      expect(lastCall('/api/ListCloudBackupItems').data.Skip).toBe(100)
    )
    await user.click(screen.getByRole('button', { name: 'All folders' }))
    await waitFor(() =>
      expect(lastCall('/api/ListCloudBackupItems').data).toMatchObject({
        Path: '',
        Skip: 0,
      })
    )
  })

  it('searches the whole owner and filters by type', async () => {
    const user = userEvent.setup()
    await openOwner(user)

    await pick(user, 'Type', 'Calendar event')
    await user.type(
      screen.getByRole('textbox', { name: 'Search this backup' }),
      'report{Enter}'
    )

    await waitFor(() =>
      expect(lastCall('/api/ListCloudBackupItems').data).toMatchObject({
        Search: 'report',
        Type: 'event',
      })
    )
    expect(lastCall('/api/ListCloudBackupItems').data.Path).toBeUndefined()
    await waitFor(() => expect(ui.tables['Search results']).toBeDefined())
    expect(ui.tables['Search results'].simpleColumns).toContain(
      'CloudBackupItemFolder'
    )
  })

  it('searches inside the open folder', async () => {
    const user = userEvent.setup()
    await openOwner(user)
    await user.click(screen.getByRole('button', { name: 'Projects' }))

    await user.click(
      await screen.findByLabelText('Only search the open folder')
    )
    await user.type(
      screen.getByRole('textbox', { name: 'Search this backup' }),
      'budget{Enter}'
    )

    await waitFor(() =>
      expect(lastCall('/api/ListCloudBackupItems').data).toMatchObject({
        Path: 'Projects',
        Search: 'budget',
        Skip: 0,
      })
    )
    await waitFor(() => expect(ui.tables['Search results']).toBeDefined())
    expect(
      screen.getByText(/in Projects and its subfolders/)
    ).toBeInTheDocument()
  })

  it('leaves out the optional filters until they are set', async () => {
    const user = userEvent.setup()
    await openOwner(user)
    const data = lastCall('/api/ListCloudBackupItems').data
    for (const key of ['Search', 'DateFrom', 'DateTo', 'Type']) {
      expect(data).not.toHaveProperty(key)
    }
  })

  it('explains a point in time without a backup', async () => {
    const user = userEvent.setup()
    results.items = getResult({
      isSuccess: false,
      isError: true,
      error: { response: { status: 404 } },
    })
    try {
      await openOwner(user)
      expect(
        screen.getByText(/There is no backup of this mailbox at this point/)
      ).toBeInTheDocument()
      expect(
        screen.queryByText(/could not be read from the destination/)
      ).not.toBeInTheDocument()
    } finally {
      results.items = getResult({ data: listing })
    }
  })

  it('shows an item with its versions and downloads it through CIPP', async () => {
    const user = userEvent.setup()
    const fetchMock = vi.fn(async () => ({
      ok: true,
      status: 200,
      headers: {
        get: () => 'attachment; filename="Quarterly report.eml"',
      },
      blob: async () => new Blob(['mail']),
    }))
    vi.stubGlobal('fetch', fetchMock)
    await openOwner(user)

    const table = ui.tables['Items in this folder']
    renderWithProviders(table.offCanvas.children(table.data[0]))

    expect(lastCall('/api/ListCloudBackupItem').data).toEqual({
      PolicyId: 'pol-1',
      TenantId: 'cid-contoso',
      Workload: 'exchange',
      OwnerId: 'u-adele',
      Key: 'items/AAA.fts',
      AsOf: '20261119T020000Z',
    })
    expect(screen.getByText('adele@contoso.com')).toBeInTheDocument()
    expect(ui.tables['Earlier versions'].data).toHaveLength(2)

    await user.click(screen.getByRole('button', { name: 'Download' }))
    await waitFor(() => expect(fetchMock).toHaveBeenCalled())
    const url = new URL(fetchMock.mock.calls[0][0], 'http://localhost')
    expect(url.pathname).toBe('/api/ExecCloudBackupDownload')
    expect(Object.fromEntries(url.searchParams)).toEqual({
      PolicyId: 'pol-1',
      TenantId: 'cid-contoso',
      Workload: 'exchange',
      OwnerId: 'u-adele',
      Key: 'items/AAA.fts',
      VersionId: 'v-1',
      Part: '0',
    })
    await waitFor(() => expect(saved).toEqual(['Quarterly report.eml']))

    const versionAction = ui.tables['Earlier versions'].actions[0]
    await act(async () => {
      await versionAction.customFunction({ VersionId: 'v-0' })
    })
    await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
    expect(fetchMock.mock.calls[1][0]).toContain('VersionId=v-0')
  })

  it('downloads every part of a large file and joins them', async () => {
    const user = userEvent.setup()
    const fetchMock = vi.fn(async () => ({
      ok: true,
      status: 200,
      headers: {
        get: (name) =>
          name === 'X-CIPP-Download-Parts'
            ? '3'
            : 'attachment; filename="Large.zip"',
      },
      blob: async () => new Blob(['part']),
    }))
    vi.stubGlobal('fetch', fetchMock)
    await openOwner(user)

    const table = ui.tables['Items in this folder']
    renderWithProviders(table.offCanvas.children(table.data[0]))
    await user.click(screen.getByRole('button', { name: 'Download' }))

    await waitFor(() => expect(saved).toEqual(['Large.zip']))
    expect(fetchMock).toHaveBeenCalledTimes(3)
    expect(
      fetchMock.mock.calls.map(([url]) =>
        new URL(url, 'http://localhost').searchParams.get('Part')
      )
    ).toEqual(['0', '1', '2'])
  })

  it('shows why a download failed', async () => {
    const user = userEvent.setup()
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: false,
        status: 404,
        json: async () => ({ Results: 'Item not found in this backup' }),
      }))
    )
    await openOwner(user)
    const table = ui.tables['Items in this folder']
    renderWithProviders(table.offCanvas.children(table.data[0]))

    await user.click(screen.getByRole('button', { name: 'Download' }))
    expect(
      await screen.findByText('Item not found in this backup')
    ).toBeInTheDocument()
  })
})

describe('Cloud Backup restore', () => {
  it('previews the selection with the default options', async () => {
    const user = userEvent.setup()
    await openOwner(user)

    act(() =>
      ui.tables['Items in this folder'].onChange(
        ui.tables['Items in this folder'].data
      )
    )
    await user.click(
      screen.getByRole('checkbox', { name: 'Select folder Projects' })
    )
    expect(
      screen.getByText('Selected: 1 item and 1 folder')
    ).toBeInTheDocument()

    const payload = await startPreview(user)
    expect(payload).toEqual({
      url: '/api/ExecCloudBackupRestore',
      data: {
        PolicyId: 'pol-1',
        TenantId: 'cid-contoso',
        Workload: 'exchange',
        OwnerId: 'u-adele',
        AsOf: '20261119T020000Z',
        Keys: ['items/AAA.fts'],
        Paths: ['Projects'],
        Location: 'RestoredFolder',
        ConflictAction: 'Skip',
        Mode: 'Preview',
      },
    })
  })

  it('restores the whole open folder when nothing is selected', async () => {
    const user = userEvent.setup()
    await openOwner(user)
    await user.click(screen.getByRole('button', { name: 'Projects' }))

    const payload = await startPreview(user)
    expect(payload.data.Paths).toEqual(['Projects'])
    expect(payload.data.Keys).toBeUndefined()
  })

  it('polls the preview and only then offers the restore', async () => {
    const user = userEvent.setup()
    jobs['job-1'] = getResult({ data: { Id: 'job-1', Status: 'Running' } })
    await openOwner(user)
    await startPreview(user)

    expect(
      await screen.findByText(/Checking the backup against/)
    ).toBeInTheDocument()
    const jobCall = ApiGetCall.mock.calls
      .map(([opts]) => opts)
      .find((opts) => opts.data?.Id === 'job-1')
    expect(
      jobCall.refetchInterval({ state: { data: { Status: 'Running' } } })
    ).toBe(3000)
    expect(
      jobCall.refetchInterval({ state: { data: { Status: 'Completed' } } })
    ).toBe(false)
    expect(
      screen.queryByRole('button', { name: /^Restore \d/ })
    ).not.toBeInTheDocument()
  })

  it('applies the exact preview after confirming the target and counts', async () => {
    const user = userEvent.setup()
    jobs['job-1'] = getResult({ data: completedPreview })
    await openOwner(user)
    const preview = await startPreview(user)

    await waitFor(() => expect(ui.tables['Restore preview']).toBeDefined())
    expect(ui.tables['Restore preview'].data[0]).toMatchObject({
      CloudBackupItemName: 'Quarterly report',
      CloudBackupRestoreAction: 'Restore',
    })
    await user.click(screen.getByRole('button', { name: 'Restore 2 items' }))
    const dialog = screen.getByRole('dialog')
    expect(dialog).toHaveTextContent(
      'Restore to Adele Vance (adele@contoso.com)'
    )
    expect(dialog).toHaveTextContent(
      '2 new, 0 overwritten and 0 restored as copies'
    )
    expect(dialog).toHaveTextContent('3 skipped and 1 cannot be restored')
    expect(ui.dialogs.Restore.api.customDataformatter()).toEqual({
      ...preview.data,
      Mode: 'Apply',
      PreviewJobId: 'job-1',
    })

    jobs['job-2'] = getResult({
      data: {
        Id: 'job-2',
        Type: 'Restore',
        Status: 'Completed',
        Summary: { Succeeded: 2, Failed: 1 },
        Result: [{ ...completedPreview.Result[0], Status: 'Succeeded' }],
      },
    })
    act(() =>
      ui.dialogs.Restore.dialogAfterEffect({
        Results: 'Queued',
        JobId: 'job-2',
      })
    )
    await waitFor(() => expect(ui.tables['Restore results']).toBeDefined())
    expect(ui.tables['Restore results'].simpleColumns).toContain(
      'CloudBackupStatus'
    )
    expect(screen.getByText('2 restored, 1 failed')).toBeInTheDocument()
  })

  it('asks for a new preview when the options change', async () => {
    const user = userEvent.setup()
    jobs['job-1'] = getResult({ data: completedPreview })
    await openOwner(user)
    await startPreview(user)
    await screen.findByRole('button', { name: 'Restore 2 items' })

    await user.click(
      screen.getByRole('radio', { name: 'Overwrite items that already exist' })
    )

    expect(screen.getByText(/changed after this preview/)).toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: 'Restore 2 items' })
    ).not.toBeInTheDocument()
  })

  it('makes a removed owner restore to another user', async () => {
    const user = userEvent.setup()
    await openOwner(user, {
      owner: 'Lee Gu (lee@contoso.com), removed from the tenant',
    })

    expect(screen.getByText(/no longer in the tenant/)).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Restore' }))

    expect(
      screen.queryByRole('radio', { name: 'The original mailbox' })
    ).not.toBeInTheDocument()
    expect(
      screen.getByRole('combobox', { name: 'User to restore to' })
    ).toBeInTheDocument()
    expect(
      screen.getByRole('button', { name: 'Preview restore' })
    ).toBeDisabled()
    expect(lastCall('/api/ListGraphRequest')).toBeUndefined()
  })

  it('restores files for another user into a new folder in their OneDrive', async () => {
    const user = userEvent.setup()
    await openOwner(user, { service: 'OneDrive' })
    await user.click(screen.getByRole('button', { name: 'Restore' }))

    await user.click(
      screen.getByRole('radio', {
        name: "Another user's OneDrive in this tenant",
      })
    )

    expect(
      screen.getByText(/Files are restored to a new folder named/)
    ).toBeInTheDocument()
    expect(
      screen.queryByRole('radio', { name: 'The original folders' })
    ).not.toBeInTheDocument()
  })

  it('offers only exports for Teams', async () => {
    const user = userEvent.setup()
    await openOwner(user, { service: 'Teams' })

    expect(
      screen.queryByRole('button', { name: 'Restore' })
    ).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Export' })).toBeInTheDocument()
    expect(
      screen.getByText(/cannot be restored into Teams/)
    ).toBeInTheDocument()
  })

  it('lets users without the restore permission browse only', async () => {
    setPermissions(['CIPP.CloudBackup.Read'])
    const user = userEvent.setup()
    await openOwner(user)

    expect(
      screen.getByText(/need the Cloud Backup restore permission/)
    ).toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: 'Restore' })
    ).not.toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: 'Export' })
    ).not.toBeInTheDocument()
    expect(ui.tables['Items in this folder'].onChange).toBeUndefined()

    const table = ui.tables['Items in this folder']
    renderWithProviders(table.offCanvas.children(table.data[0]))
    expect(
      screen.queryByRole('button', { name: 'Download' })
    ).not.toBeInTheDocument()
    expect(ui.tables['Earlier versions'].actions).toBeUndefined()
  })
})

describe('Cloud Backup export', () => {
  it('starts an export and downloads the zip when it is ready', async () => {
    const user = userEvent.setup()
    const fetchMock = vi.fn(async () => ({
      ok: true,
      status: 200,
      headers: { get: () => null },
      blob: async () => new Blob(['zip']),
    }))
    vi.stubGlobal('fetch', fetchMock)
    await openOwner(user)
    await user.click(screen.getByRole('button', { name: 'Projects' }))

    await user.click(screen.getByRole('button', { name: 'Export' }))
    expect(screen.getByRole('dialog')).toHaveTextContent(
      'Export everything in Projects from Adele Vance'
    )
    expect(ui.dialogs.Export.api.customDataformatter()).toEqual({
      PolicyId: 'pol-1',
      TenantId: 'cid-contoso',
      Workload: 'exchange',
      OwnerId: 'u-adele',
      AsOf: '20261119T020000Z',
      Paths: ['Projects'],
    })

    jobs['job-9'] = getResult({
      data: {
        Id: 'job-9',
        Type: 'Export',
        Status: 'Completed',
        Summary: { Items: 12, Failed: 1 },
        DownloadAvailable: true,
        ExpiresAt: '2099-01-01T00:00:00Z',
      },
    })
    act(() => ui.dialogs.Export.dialogAfterEffect({ JobId: 'job-9' }))
    await user.click(
      await screen.findByRole('button', { name: 'Download export' })
    )
    expect(screen.getByText('12 items exported, 1 failed')).toBeInTheDocument()
    await waitFor(() => expect(fetchMock).toHaveBeenCalled())
    expect(fetchMock.mock.calls[0][0]).toBe(
      '/api/ExecCloudBackupDownload?JobId=job-9&Part=0'
    )
    await waitFor(() => expect(saved).toEqual(['export-job-9.zip']))
  })
})

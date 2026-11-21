import React from 'react'
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import router from 'next/router'
import { renderWithProviders } from '../test-utils'
import TimeAgo from 'javascript-time-ago'
import en from 'javascript-time-ago/locale/en'
import { api, getResult, postResult } from '../mocks/api-call'
import { ApiGetCall } from '../../src/api/ApiCall'

vi.mock('../../src/api/ApiCall', async () =>
  (await import('../mocks/api-call')).apiCallMock()
)
const table = vi.hoisted(() => ({ props: null }))
vi.mock('../../src/components/CippComponents/CippTablePage.jsx', () => ({
  CippTablePage: (props) => {
    table.props = props
    return <div>{props.cardButton}</div>
  },
}))

const ui = vi.hoisted(() => ({ tables: {} }))
vi.mock('../../src/components/CippTable/CippDataTable', () => ({
  CippDataTable: (props) => {
    ui.tables[props.title] = props
    return <div data-testid={`table-${props.title}`} />
  },
}))

import ListPage from '../../src/pages/cloud-backup/policies/index.jsx'
import AddPage from '../../src/pages/cloud-backup/policies/add.jsx'
import EditPage from '../../src/pages/cloud-backup/policies/edit.jsx'

const destinations = getResult({
  data: [
    {
      Id: 'dest-1',
      Name: 'Azure prod',
      Location: 'cippbackups/content',
      LastTest: { Versioning: 'Enabled', ContentReady: true },
    },
    {
      Id: 'dest-2',
      Name: 'Old bucket',
      Location: 'old-bucket',
      LastTest: { Versioning: 'Suspended', ContentReady: false },
    },
    { Id: 'dest-3', Name: 'Untested', Location: 'new-bucket' },
  ],
})
const noDestinations = getResult({ data: [] })
const tenants = getResult({
  data: [
    {
      defaultDomainName: 'AllTenants',
      displayName: '*All Tenants',
      customerId: 'AllTenants',
    },
    {
      defaultDomainName: 'contoso.com',
      displayName: 'Contoso',
      customerId: 'cid-contoso',
    },
  ],
})
const groups = getResult({
  data: { Results: [{ Id: 'grp-1', Name: 'Gold customers' }] },
})
const emptyGet = getResult()
const existingPolicy = getResult({
  data: [
    {
      Id: 'pol-1',
      Name: 'Mail and files',
      Enabled: true,
      DestinationId: 'dest-1',
      DestinationName: 'Azure prod',
      Tenants: [{ label: 'Gold customers', value: 'grp-1', type: 'Group' }],
      Workloads: '["exchange","onedrive"]',
      Schedules: '{"exchange":"12h","onedrive":"1d"}',
      Exclusions: {
        Users: ['ceo@contoso.com'],
        Groups: ['5f0c2a6e-0000-4000-8000-000000000001'],
        Sites: ['https://contoso.sharepoint.com/sites/archive'],
      },
      RetentionDays: 30,
      Encryption: true,
    },
  ],
})

const routeGets = (destinationResult) => (opts) => {
  if (opts.url === '/api/ListCloudBackupDestinations') return destinationResult
  if (opts.url?.startsWith('/api/ListTenants')) return tenants
  if (opts.url === '/api/ListTenantGroups') return groups
  if (opts.url === '/api/ListCloudBackupPolicies') return existingPolicy
  return emptyGet
}

let post
beforeEach(() => {
  vi.clearAllMocks()
  post = postResult()
  api.post = () => post
  api.get = routeGets(destinations)
})

afterEach(() => {
  router.query = {}
})

try {
  TimeAgo.addDefaultLocale(en)
} catch {
  // already registered by an earlier file in this worker
}

const addValue = async (user, combobox, value) => {
  await user.type(screen.getByRole('combobox', { name: combobox }), value)
  await user.click(
    await screen.findByRole('option', { name: `Add option: "${value}"` })
  )
}

const pickOption = async (user, combobox, option) => {
  await user.click(screen.getByRole('combobox', { name: combobox }))
  await user.click(await screen.findByRole('option', { name: option }))
}

describe('Cloud Backup policy form', () => {
  it('asks for a destination first when none exist', async () => {
    api.get = routeGets(noDestinations)
    renderWithProviders(<AddPage />)

    expect(
      await screen.findByText(/Add a destination first/)
    ).toBeInTheDocument()
    expect(
      screen.getByRole('link', { name: 'Add destination' })
    ).toHaveAttribute('href', '/cloud-backup/destinations/add')
    expect(
      screen.queryByRole('combobox', { name: 'Destination' })
    ).not.toBeInTheDocument()
  })

  it('backs up every service by default on the default schedules', async () => {
    renderWithProviders(<AddPage />)

    expect(
      await screen.findByRole('spinbutton', {
        name: /Keep deleted and changed/,
      })
    ).toHaveValue(90)
    for (const name of ['Exchange Online', 'OneDrive', 'SharePoint', 'Teams']) {
      expect(screen.getByRole('switch', { name })).toBeChecked()
    }
    const schedule = (name) =>
      screen.getByRole('combobox', { name: `${name} schedule` })
    expect(schedule('Exchange Online')).toHaveValue('Every 4 hours')
    expect(schedule('Teams')).toHaveValue('Every 4 hours')
    expect(schedule('OneDrive')).toHaveValue('Every 6 hours')
    expect(schedule('SharePoint')).toHaveValue('Every 6 hours')
    expect(screen.getByRole('switch', { name: 'Enabled' })).toBeChecked()
    expect(
      screen.getByRole('switch', { name: 'Encrypt backups' })
    ).not.toBeChecked()
  })

  it('offers 4 hours only for Exchange and Teams', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)

    await user.click(
      await screen.findByRole('combobox', { name: 'OneDrive schedule' })
    )
    expect(
      await screen.findByRole('option', { name: 'Every 12 hours' })
    ).toBeInTheDocument()
    expect(
      screen.getByRole('option', { name: 'Every day' })
    ).toBeInTheDocument()
    expect(
      screen.queryByRole('option', { name: 'Every 4 hours' })
    ).not.toBeInTheDocument()
  })

  it('hides the schedule of a service that is turned off', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)

    await user.click(await screen.findByRole('switch', { name: 'Teams' }))
    expect(
      screen.queryByRole('combobox', { name: 'Teams schedule' })
    ).not.toBeInTheDocument()
  })

  it('needs at least one service', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)

    for (const name of ['Exchange Online', 'OneDrive', 'SharePoint', 'Teams']) {
      await user.click(await screen.findByRole('switch', { name }))
    }
    expect(
      await screen.findByText('Choose at least one service to back up')
    ).toBeInTheDocument()
  })

  it.each([
    ['5', 'Keep earlier versions for at least 7 days'],
    ['4000', 'Keep earlier versions for at most 3650 days (10 years)'],
    ['', 'Enter how many days to keep earlier versions'],
  ])('rejects a retention of "%s" days', async (days, message) => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)

    const retention = await screen.findByRole('spinbutton', {
      name: /Keep deleted and changed/,
    })
    await user.clear(retention)
    if (days) await user.type(retention, days)

    expect(await screen.findByText(message)).toBeInTheDocument()
  })

  it('warns when the destination does not have versioning on', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)

    await pickOption(user, 'Destination', 'Old bucket (old-bucket)')
    expect(
      await screen.findByText(/Versioning is off on this destination/)
    ).toBeInTheDocument()

    await pickOption(user, 'Destination', 'Untested (new-bucket)')
    expect(
      await screen.findByText(/hasn't confirmed that versioning is on/)
    ).toBeInTheDocument()

    await pickOption(user, 'Destination', 'Azure prod (cippbackups/content)')
    await waitFor(() =>
      expect(
        screen.queryByText(/Versioning is off on this destination/)
      ).not.toBeInTheDocument()
    )
    expect(
      screen.queryByText(/hasn't confirmed that versioning is on/)
    ).not.toBeInTheDocument()
  })

  it('rejects a site exclusion that is not a SharePoint address', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)

    await screen.findByRole('combobox', { name: 'Excluded sites' })
    await addValue(user, 'Excluded sites', 'archive')
    expect(
      await screen.findByText(/Enter full site addresses/)
    ).toBeInTheDocument()
  })

  it('offers user and group pickers once a single tenant is chosen', async () => {
    const user = userEvent.setup()
    const { ApiGetCallWithPagination } = await import('../../src/api/ApiCall')
    renderWithProviders(<AddPage />)

    expect(
      await screen.findByText(/To pick from a list, select a single tenant/)
    ).toBeInTheDocument()
    await pickOption(user, 'Tenants', 'Contoso (contoso.com)')
    expect(
      await screen.findByText(/Pick users and groups from the selected tenant/)
    ).toBeInTheDocument()
    await waitFor(() =>
      expect(
        ApiGetCallWithPagination.mock.calls.some(
          ([opts]) =>
            opts?.url === '/api/ListGraphRequest' &&
            opts?.data?.Endpoint === 'users' &&
            JSON.stringify(opts).includes('contoso.com')
        )
      ).toBe(true)
    )
  })

  it('keeps Submit disabled until the required fields are filled', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)

    await user.type(
      await screen.findByRole('textbox', { name: 'Policy name' }),
      'Nightly'
    )
    expect(screen.getByRole('button', { name: 'Submit' })).toBeDisabled()
  })

  it('posts services, schedules and exclusions as plain values', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)

    await user.type(
      await screen.findByRole('textbox', { name: 'Policy name' }),
      'Everything'
    )
    await pickOption(user, 'Destination', 'Azure prod (cippbackups/content)')
    await pickOption(user, 'Tenants', 'Contoso (contoso.com)')
    await user.click(screen.getByRole('switch', { name: 'Teams' }))
    await pickOption(user, 'SharePoint schedule', 'Every 12 hours')
    await addValue(user, 'Excluded users', 'ceo@contoso.com')
    await addValue(
      user,
      'Excluded sites',
      'https://contoso.sharepoint.com/sites/archive'
    )

    const submit = screen.getByRole('button', { name: 'Submit' })
    await waitFor(() => expect(submit).toBeEnabled())
    await user.click(submit)

    await waitFor(() => expect(post.mutate).toHaveBeenCalledTimes(1))
    const { url, data } = post.mutate.mock.calls[0][0]
    expect(url).toBe('/api/ExecCloudBackupPolicy')
    expect(data).toMatchObject({
      Action: 'Add',
      Name: 'Everything',
      Enabled: true,
      DestinationId: 'dest-1',
      Workloads: ['exchange', 'onedrive', 'sharepoint'],
      Schedules: { exchange: '4h', onedrive: '6h', sharepoint: '12h' },
      Exclusions: {
        Users: ['ceo@contoso.com'],
        Groups: [],
        Sites: ['https://contoso.sharepoint.com/sites/archive'],
      },
      RetentionDays: 90,
      Encryption: false,
    })
    expect(data).not.toHaveProperty('ConfigAreas')
    expect(data.Tenants).toEqual([
      expect.objectContaining({
        label: 'Contoso (contoso.com)',
        value: 'contoso.com',
        type: 'Tenant',
      }),
    ])
  })

  it('loads an existing policy and posts the Edit action', async () => {
    const user = userEvent.setup()
    router.query = { id: 'pol-1' }
    renderWithProviders(<EditPage />)

    expect(
      await screen.findByDisplayValue('Mail and files')
    ).toBeInTheDocument()
    expect(
      screen.getByRole('spinbutton', { name: /Keep deleted and changed/ })
    ).toHaveValue(30)
    expect(screen.getByText('Gold customers')).toBeInTheDocument()
    expect(
      screen.getByRole('switch', { name: 'Exchange Online' })
    ).toBeChecked()
    expect(screen.getByRole('switch', { name: 'Teams' })).not.toBeChecked()
    expect(
      screen.getByRole('combobox', { name: 'Exchange Online schedule' })
    ).toHaveValue('Every 12 hours')
    expect(screen.getByText('ceo@contoso.com')).toBeInTheDocument()

    await user.clear(screen.getByRole('textbox', { name: 'Policy name' }))
    await user.type(
      screen.getByRole('textbox', { name: 'Policy name' }),
      'Mail only'
    )
    const submit = screen.getByRole('button', { name: 'Submit' })
    await waitFor(() => expect(submit).toBeEnabled())
    await user.click(submit)

    await waitFor(() => expect(post.mutate).toHaveBeenCalledTimes(1))
    expect(post.mutate.mock.calls[0][0].data).toMatchObject({
      Action: 'Edit',
      Id: 'pol-1',
      Name: 'Mail only',
      DestinationId: 'dest-1',
      Tenants: [{ label: 'Gold customers', value: 'grp-1', type: 'Group' }],
      Workloads: ['exchange', 'onedrive'],
      Schedules: { exchange: '12h', onedrive: '1d' },
      Exclusions: {
        Users: ['ceo@contoso.com'],
        Groups: ['5f0c2a6e-0000-4000-8000-000000000001'],
        Sites: ['https://contoso.sharepoint.com/sites/archive'],
      },
      RetentionDays: 30,
      Encryption: true,
    })
  })
})

describe('Cloud Backup policies list', () => {
  const action = (label) =>
    table.props.actions.find((item) => item.label === label)

  it('lists the policies of the selected tenant, bypassing the response cache', () => {
    renderWithProviders(<ListPage />)

    expect(table.props.apiUrl).toBe('/api/ListCloudBackupPolicies')
    expect(table.props.queryKey).toBe('ListCloudBackupPolicies-testdomain.com')
    expect(table.props.apiData).toEqual({ InvalidateCIPPCache: true })
    expect(screen.getByRole('link', { name: 'Add Policy' })).toHaveAttribute(
      'href',
      '/cloud-backup/policies/add'
    )
  })

  it('offers to revoke permissions no policy needs and keeps the result in view', () => {
    let unused = getResult({
      data: [
        {
          TenantId: 'cid-fabrikam',
          Tenant: 'fabrikam.com',
          Permissions: ['Chat.Read.All', 'Team.ReadBasic.All'],
          GrantedAt: '2026-11-20T00:00:00Z',
        },
      ],
    })
    const route = routeGets(destinations)
    api.get = (opts) =>
      opts.url === '/api/ListCloudBackupUnusedPermissions'
        ? unused
        : route(opts)
    renderWithProviders(<ListPage />)
    const { rerender } = render(table.props.tableFilter)

    const unusedCall = ApiGetCall.mock.calls
      .map(([opts]) => opts)
      .find((opts) => opts.url === '/api/ListCloudBackupUnusedPermissions')
    expect(unusedCall).toMatchObject({
      data: { tenantFilter: 'testdomain.com', InvalidateCIPPCache: true },
      queryKey: 'ListCloudBackupUnusedPermissions-testdomain.com',
    })
    const offer = ui.tables['Permissions No Policy Needs']
    expect(offer.data[0]).toMatchObject({
      Tenant: 'fabrikam.com',
      CloudBackupPermissions: 'Chat.Read.All, Team.ReadBasic.All',
      CloudBackupGrantedAt: '2026-11-20T00:00:00Z',
    })
    expect(offer.actions[0]).toMatchObject({
      label: 'Revoke Permissions',
      type: 'POST',
      url: '/api/ExecCloudBackupRevokePermissions',
      data: { TenantId: 'TenantId' },
      relatedQueryKeys: ['ListCloudBackupUnusedPermissions*'],
    })

    unused = getResult({ data: [] })
    rerender(React.cloneElement(table.props.tableFilter))
    expect(
      screen.getByText('No cloud backup permissions are left to revoke.')
    ).toBeInTheDocument()
  })

  it('shows no revoke offer when every tenant is still backed up', () => {
    renderWithProviders(<ListPage />)
    const { container } = renderWithProviders(table.props.tableFilter)
    expect(container).toBeEmptyDOMElement()
  })

  it('refreshes the revoke offer when a policy is deleted', () => {
    renderWithProviders(<ListPage />)
    expect(action('Delete Policy').relatedQueryKeys).toContain(
      'ListCloudBackupUnusedPermissions*'
    )
  })

  it('runs a policy now and refreshes the runs', () => {
    renderWithProviders(<ListPage />)

    const runNow = action('Run Backup Now')
    expect(runNow).toMatchObject({
      type: 'POST',
      url: '/api/ExecCloudBackupRun',
      data: { PolicyId: 'Id' },
    })
    expect(runNow.relatedQueryKeys).toContain('ListCloudBackupRuns*')
  })

  it('offers key rotation only for encrypted policies', () => {
    renderWithProviders(<ListPage />)

    const rotate = action('Rotate Encryption Key')
    expect(rotate.data).toEqual({ Action: '!RotateKey', Id: 'Id' })
    expect(rotate.condition({ Encryption: true })).toBe(true)
    expect(rotate.condition({ Encryption: false })).toBe(false)
  })

  it('deletes with a literal Delete action', () => {
    renderWithProviders(<ListPage />)

    expect(action('Delete Policy').data).toEqual({
      Action: '!Delete',
      Id: 'Id',
    })
    expect(action('Edit Policy').link).toBe(
      '/cloud-backup/policies/edit?id=[Id]'
    )
  })

  it('asks the backend to grant permissions again for every tenant', () => {
    renderWithProviders(<ListPage />)

    expect(action('Grant Permissions')).toMatchObject({
      type: 'POST',
      url: '/api/ExecCloudBackupPolicy',
      data: { Action: '!GrantPermissions', Id: 'Id' },
    })
  })

  it('shows services and the permission state in the table rows', () => {
    renderWithProviders(<ListPage />)

    const row = table.props.dataMap({
      Workloads: ['teams', 'exchange'],
      PermissionStatus:
        '{"cid-1":{"Status":"Granted"},"cid-2":{"Status":"Failed","Message":"No GDAP role"}}',
    })
    expect(row.CloudBackupWorkloads).toBe('Exchange Online, Teams')
    expect(row.CloudBackupPermissions).toBe('1 of 2 tenants failed')
    expect(
      table.props.dataMap({ PermissionStatus: {} }).CloudBackupPermissions
    ).toBe('Not checked yet')
    expect(
      table.props.dataMap({
        PermissionStatus: { 'cid-1': { Status: 'Granted' } },
      }).CloudBackupPermissions
    ).toBe('All granted')
  })

  it("describes the policy and each tenant's permissions in the details drawer", async () => {
    const user = userEvent.setup()
    renderWithProviders(<ListPage />)
    renderWithProviders(
      table.props.offCanvas.children({
        Id: 'pol-1',
        Name: 'Mail and files',
        Enabled: true,
        DestinationName: 'Azure prod',
        TenantSummary: 'All tenants',
        Tenants: [
          { label: 'All Tenants', value: 'AllTenants', type: 'Tenant' },
        ],
        Workloads: ['exchange', 'sharepoint'],
        Schedules: { exchange: '4h', sharepoint: '1d' },
        Exclusions: { Users: ['ceo@contoso.com'], Groups: [], Sites: [] },
        PermissionStatus: {
          'cid-contoso': {
            Status: 'Failed',
            Message: 'CIPP has no GDAP role that can grant app permissions',
            CheckedAt: '2026-11-19T10:00:00Z',
          },
          'cid-fabrikam': { Status: 'Granted' },
        },
        RetentionDays: 365,
        Encryption: true,
        KeyCount: 2,
      })
    )

    expect(screen.getByText('Policy: Mail and files')).toBeInTheDocument()
    expect(screen.getByText(/Every 4 hours/)).toBeInTheDocument()
    expect(screen.getByText(/Every day/)).toBeInTheDocument()
    expect(screen.getByText('ceo@contoso.com')).toBeInTheDocument()
    expect(screen.getByText('365 days')).toBeInTheDocument()
    expect(screen.getByText('On (2 keys)')).toBeInTheDocument()
    expect(screen.getByText('Contoso (contoso.com)')).toBeInTheDocument()
    expect(screen.getByText('cid-fabrikam')).toBeInTheDocument()
    expect(
      screen.getByText('CIPP has no GDAP role that can grant app permissions')
    ).toBeInTheDocument()

    const retry = screen.getAllByRole('button', { name: 'Grant again' })
    expect(retry).toHaveLength(1)
    await user.click(retry[0])
    expect(
      await screen.findByText(/needs in Contoso \(contoso.com\) again/)
    ).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Confirm' }))
    await waitFor(() => expect(post.mutate).toHaveBeenCalled())
    expect(post.mutate.mock.calls.at(-1)[0]).toMatchObject({
      url: '/api/ExecCloudBackupPolicy',
      data: {
        Action: 'GrantPermissions',
        Id: 'pol-1',
        TenantId: 'cid-contoso',
      },
    })
  })
})

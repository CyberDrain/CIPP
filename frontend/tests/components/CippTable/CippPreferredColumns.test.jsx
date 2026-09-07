import React, { useState } from 'react'
import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { vi } from 'vitest'
import { renderWithProviders, settingsWith } from '../../test-utils'
import { SettingsContext } from '../../../src/contexts/settings-context'
import { CippDataTable } from '../../../src/components/CippTable/CippDataTable'
import router from '../../mocks/next-router'

vi.mock('../../../src/api/ApiCall', async () => (await import('../../mocks/api-call')).apiCallMock())
import { api, paginatedResult } from '../../mocks/api-call'

const page = 'identity/administration/users'
const idleResult = paginatedResult([], { isSuccess: false })
const tenantResults = {
  A: paginatedResult([{ displayName: 'Alice', mail: 'alice@example.com', department: 'IT' }]),
  B: paginatedResult([
    { displayName: 'Bob', mail: 'bob@example.com', department: 'Sales', jobTitle: 'Manager' },
    { displayName: 'Carol', mail: 'carol@example.com', department: 'HR', jobTitle: 'Analyst' },
  ]),
}
const customColumns = [
  { id: 'displayName', accessorKey: 'displayName', header: 'Display Name' },
  { id: 'mail', accessorKey: 'mail', header: 'Mail' },
]
const modes = [
  ['custom', { columns: customColumns }],
  ['simple', { simpleColumns: ['displayName', 'mail'] }],
  ['automatic', {}],
]

function Example({ tableProps, saved = {}, otherSaved = {} }) {
  const [settings, setSettings] = useState(() => settingsWith({
    currentTenant: 'A',
    columnDefaults: { [page]: saved, ...otherSaved },
  }))
  const [tableKey, setTableKey] = useState(0)
  return (
    <SettingsContext.Provider value={{
      ...settings,
      handleUpdate: (update) => setSettings((previous) => ({ ...previous, ...update })),
    }}>
      <button onClick={() => setSettings((previous) => ({ ...previous, currentTenant: 'B' }))}>
        Tenant B
      </button>
      <button onClick={() => setTableKey((key) => key + 1)}>Reload table</button>
      <CippDataTable
        key={tableKey}
        api={{ url: '/api/TestPreferredColumns', dataKey: 'Results', data: { tenantFilter: settings.currentTenant } }}
        queryKey={`preferred-${settings.currentTenant}`}
        viewMode="table"
        {...tableProps}
      />
    </SettingsContext.Provider>
  )
}

const columnCheckbox = (name) => within(screen.getByRole('menuitem', { name })).getByRole('checkbox')

beforeEach(() => {
  router.pathname = `/${page}`
  api.paginated = (options) => tenantResults[options.data?.tenantFilter] || idleResult
})

afterEach(() => {
  router.pathname = '/'
})

describe.each(modes)('preferred columns with %s columns', (_mode, tableProps) => {
  it('keeps saved selections after switching tenants with different API data and remounting', async () => {
    const user = userEvent.setup()
    renderWithProviders(<Example tableProps={tableProps} />)
    await screen.findByText('1-1 of 1')
    await user.click(screen.getByRole('button', { name: 'Columns' }))
    if (!columnCheckbox('Department').checked) await user.click(columnCheckbox('Department'))
    await user.click(columnCheckbox('Mail'))
    await user.click(screen.getByRole('menuitem', { name: 'Save as preferred columns' }))

    await user.click(screen.getByRole('button', { name: 'Tenant B' }))
    await screen.findByText('1-2 of 2')
    await user.click(screen.getByRole('button', { name: 'Columns' }))
    expect(columnCheckbox('Department')).toBeChecked()
    expect(columnCheckbox('Mail')).not.toBeChecked()
    // A field absent from the saved preference retains this table's default.
    expect(columnCheckbox('Job Title').checked).toBe(_mode === 'automatic')
    await user.click(columnCheckbox('Department'))
    await user.click(screen.getByRole('menuitem', { name: 'Reset to preferred columns' }))
    await user.click(screen.getByRole('button', { name: 'Columns' }))
    expect(columnCheckbox('Department')).toBeChecked()
    expect(columnCheckbox('Mail')).not.toBeChecked()
    expect(columnCheckbox('Job Title').checked).toBe(_mode === 'automatic')
    await user.keyboard('{Escape}')

    await user.click(screen.getByRole('button', { name: 'Reload table' }))
    await screen.findByText('1-2 of 2')
    await user.click(screen.getByRole('button', { name: 'Columns' }))
    expect(columnCheckbox('Department')).toBeChecked()
    expect(columnCheckbox('Mail')).not.toBeChecked()
  })

  it('applies existing preferences when API data arrives after mount', async () => {
    const user = userEvent.setup()
    renderWithProviders(<Example tableProps={tableProps} saved={{ department: true, mail: false }} />)
    await screen.findByText('1-1 of 1')
    await user.click(screen.getByRole('button', { name: 'Columns' }))
    await waitFor(() => expect(columnCheckbox('Department')).toBeChecked())
    expect(columnCheckbox('Mail')).not.toBeChecked()
    expect(columnCheckbox('Display Name')).toBeChecked()
  })
})

it('does not apply the parent page preference to an unkeyed dialog table', async () => {
  const user = userEvent.setup()
  renderWithProviders(<Example
    tableProps={{ columns: customColumns, isInDialog: true }}
    saved={{ department: true, mail: false }}
  />)
  await screen.findByText('1-1 of 1')
  await user.click(screen.getByRole('button', { name: 'Columns' }))
  expect(columnCheckbox('Department')).not.toBeChecked()
  expect(columnCheckbox('Mail')).toBeChecked()
})

it('uses the explicit persistence key for a dialog table', async () => {
  const user = userEvent.setup()
  renderWithProviders(<Example
    tableProps={{ columns: customColumns, isInDialog: true, persistenceKey: 'related-users' }}
    saved={{ department: false, mail: true }}
    otherSaved={{ 'related-users': { department: true, mail: false } }}
  />)
  await screen.findByText('1-1 of 1')
  await user.click(screen.getByRole('button', { name: 'Columns' }))
  expect(columnCheckbox('Department')).toBeChecked()
  expect(columnCheckbox('Mail')).not.toBeChecked()
})

it('does not restore deleted preferences after a tenant switch or reload', async () => {
  const user = userEvent.setup()
  renderWithProviders(<Example
    tableProps={{ simpleColumns: ['displayName', 'mail'] }}
    saved={{ department: true, mail: false }}
  />)
  await screen.findByText('1-1 of 1')
  await user.click(screen.getByRole('button', { name: 'Columns' }))
  await user.click(screen.getByRole('menuitem', { name: 'Delete preferred columns' }))
  await user.click(screen.getByRole('button', { name: 'Tenant B' }))
  await screen.findByText('1-2 of 2')
  await user.click(screen.getByRole('button', { name: 'Columns' }))
  expect(columnCheckbox('Department')).not.toBeChecked()
  expect(columnCheckbox('Mail')).toBeChecked()
  await user.keyboard('{Escape}')
  await user.click(screen.getByRole('button', { name: 'Reload table' }))
  await screen.findByText('1-2 of 2')
  await user.click(screen.getByRole('button', { name: 'Columns' }))
  expect(columnCheckbox('Department')).not.toBeChecked()
  expect(columnCheckbox('Mail')).toBeChecked()
})

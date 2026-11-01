import React, { useState } from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, within, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithProviders, settingsWith } from '../../test-utils'
import { SettingsContext } from '../../../src/contexts/settings-context'
import { CippBulkInviteGuestDrawer } from '../../../src/components/CippComponents/CippBulkInviteGuestDrawer'
import {
  ApiGetCall,
  ApiPostCall,
  ApiGetCallWithPagination,
} from '../../../src/api/ApiCall'

vi.mock('../../../src/api/ApiCall', () => ({
  ApiGetCall: vi.fn(),
  ApiPostCall: vi.fn(),
  ApiGetCallWithPagination: vi.fn(),
}))

// Same stubs as CippBulkUserDrawer.test.jsx: the preview table, results panel and JSON view play
// no part in the tenant under test and their static imports exhaust the worker.
vi.mock('../../../src/components/CippComponents/CippApiResults', () => ({
  CippApiResults: () => null,
}))
vi.mock('../../../src/components/CippTable/CippDataTable', () => ({
  CippDataTable: () => <div data-testid="CippDataTable" />,
  default: () => <div data-testid="CippDataTable" />,
}))
vi.mock('../../../src/components/CippFormPages/CippJSONView', () => ({
  default: () => null,
}))
vi.mock('../../../src/components/CippComponents/CippOffCanvas', () => ({
  CippOffCanvas: ({ visible, children, footer }) =>
    visible ? (
      <div data-testid="CippOffCanvas">
        {children}
        {footer}
      </div>
    ) : null,
}))

const idleGet = {
  isSuccess: false,
  isFetching: false,
  isError: false,
  data: undefined,
  refetch: vi.fn(),
}

let mutateSpy

// The Users page stays mounted when the tenant selector changes, so the drawer must pick up the
// tenant that is current when it is opened, not the one captured when the form was created.
function TenantSwitchHarness() {
  const [tenant, setTenant] = useState('tenant-a.example.com')
  return (
    <SettingsContext.Provider value={settingsWith({ currentTenant: tenant })}>
      <button onClick={() => setTenant('tenant-b.example.com')}>
        Switch tenant
      </button>
      <CippBulkInviteGuestDrawer />
    </SettingsContext.Provider>
  )
}

describe('CippBulkInviteGuestDrawer - tenant switch', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    mutateSpy = vi.fn()
    ApiGetCall.mockImplementation(() => idleGet)
    ApiGetCallWithPagination.mockImplementation(() => ({
      ...idleGet,
      fetchNextPage: vi.fn(),
    }))
    ApiPostCall.mockImplementation(() => ({
      isLoading: false,
      isSuccess: false,
      isError: false,
      mutate: mutateSpy,
    }))
  })

  it('sends every invite to the tenant selected when the drawer is opened', async () => {
    const user = userEvent.setup()
    renderWithProviders(<TenantSwitchHarness />)

    await user.click(screen.getByRole('button', { name: 'Switch tenant' }))
    await user.click(screen.getByRole('button', { name: 'Bulk Invite Guests' }))

    await user.click(screen.getByRole('button', { name: 'Add Guest Manually' }))
    const dialog = await screen.findByRole('dialog')
    const [displayName, mail] = within(dialog).getAllByRole('textbox')
    await user.type(displayName, 'Guest User')
    await user.type(mail, 'guest@example.com')
    await user.click(within(dialog).getByRole('button', { name: 'Add' }))
    await waitFor(() => {
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    })

    await user.click(screen.getByRole('button', { name: 'Send Invites' }))

    expect(mutateSpy).toHaveBeenCalledTimes(1)
    const { data } = mutateSpy.mock.calls[0][0]
    expect(data).toHaveLength(1)
    expect(data[0].tenantFilter).toBe('tenant-b.example.com')
  }, 30000)
})

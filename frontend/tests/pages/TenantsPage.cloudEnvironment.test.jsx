import React from 'react'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithProviders } from '../test-utils'
import { api, getResult, postResult } from '../mocks/api-call'
import { CippApiDialog } from '../../src/components/CippComponents/CippApiDialog'
import { usePermissions } from '../../src/hooks/use-permissions'

// Capture the props the page hands to its table so the tests run the real action definition.
const tableProps = vi.hoisted(() => ({ current: null }))
vi.mock('../../src/api/ApiCall', async () =>
  (await import('../mocks/api-call')).apiCallMock()
)
vi.mock('../../src/hooks/use-permissions', () => ({
  usePermissions: vi.fn(),
}))
vi.mock('../../src/components/CippComponents/CippTablePage.jsx', () => ({
  CippTablePage: (props) => {
    tableProps.current = props
    return <div data-testid="table-page-stub" />
  },
}))

import Page from '../../src/pages/tenant/administration/tenants/index.jsx'

// The backend accepts exactly these values (Invoke-EditTenantCloudEnvironment)
const BACKEND_ALLOWED = ['Commercial', 'USGovHigh', 'USGovDoD']

const tenant = {
  customerId: 'cccccccc-1111-2222-3333-444444444444',
  displayName: 'Contoso Gov',
  defaultDomainName: 'contoso.us',
  cloudEnvironment: 'Commercial',
}

const emptyGet = getResult()

const renderPage = (permissions) => {
  usePermissions.mockReturnValue({
    checkPermissions: (required) =>
      required.every((perm) => permissions.includes(perm)),
  })
  api.get = () => emptyGet
  const { unmount } = renderWithProviders(<Page />)
  const props = tableProps.current
  unmount()
  return props
}

const getAction = (props) =>
  props.actions.find((entry) => entry.label === 'Set Cloud Environment')

describe('Tenants page - cloud environment', () => {
  let post

  beforeEach(() => {
    post = postResult()
    api.post = () => post
  })

  it('shows the cloud environment column', () => {
    const props = renderPage(['CIPP.AppSettings.ReadWrite'])
    expect(props.simpleColumns).toContain('cloudEnvironment')
  })

  it('offers Set Cloud Environment as a single-row action posting to the override endpoint', () => {
    const action = getAction(renderPage(['CIPP.AppSettings.ReadWrite']))
    expect(action).toBeDefined()
    expect(action.url).toBe('/api/EditTenantCloudEnvironment')
    expect(action.type).toBe('POST')
    expect(action.hideBulk).toBe(true)
    expect(action.data).toEqual({ customerId: 'customerId' })
    expect(action.condition(tenant)).toBe(true)
  })

  it('hides the action from users without CIPP.AppSettings.ReadWrite', () => {
    const action = getAction(renderPage(['Tenant.Config.ReadWrite']))
    expect(action.condition(tenant)).toBe(false)
  })

  it('only offers the values the backend accepts', () => {
    const action = getAction(renderPage(['CIPP.AppSettings.ReadWrite']))
    const field = action.fields.find((f) => f.name === 'cloudEnvironment')
    expect(field.required).toBe(true)
    expect(field.multiple).toBe(false)
    expect(field.creatable).toBe(false)
    expect(field.options.map((o) => o.value)).toEqual(BACKEND_ALLOWED)
  })

  it('posts the tenant id and the selected cloud', async () => {
    const user = userEvent.setup()
    const action = getAction(renderPage(['CIPP.AppSettings.ReadWrite']))
    renderWithProviders(
      <CippApiDialog
        createDialog={{ open: true, handleClose: vi.fn() }}
        title="Set Cloud Environment"
        fields={action.fields}
        api={action}
        row={tenant}
      />
    )

    await user.click(screen.getByRole('combobox'))
    await user.click(
      await screen.findByRole('option', { name: 'US Government (GCC High)' })
    )
    await user.click(screen.getByRole('button', { name: 'Confirm' }))

    await waitFor(() => {
      expect(post.mutate).toHaveBeenCalledTimes(1)
    })
    const { url, data } = post.mutate.mock.calls[0][0]
    expect(url).toBe('/api/EditTenantCloudEnvironment')
    expect(data.customerId).toBe(tenant.customerId)
    // The backend accepts a plain string or the { label, value } object
    const sent = data.cloudEnvironment?.value ?? data.cloudEnvironment
    expect(sent).toBe('USGovHigh')
  })
})

// redanthrax/CIPP#4: the tenant offcanvas portal links follow a government tenant's cloud.
import React from 'react'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithProviders } from '../../test-utils'
import { CippTenantSelector } from '../../../src/components/CippComponents/CippTenantSelector'
import { tenantsContosoFabrikam } from '../../mocks/fixtures'

// url-keyed api state + per-test router, both hoisted for the mock factories
const apiState = vi.hoisted(() => ({ tenants: {}, details: {}, urls: [] }))
const routerState = vi.hoisted(() => ({ router: null }))
const cloudState = vi.hoisted(() => ({ cloud: undefined }))

vi.mock('../../../src/api/ApiCall', () => ({
  ApiPostCall: () => ({
    mutate: () => {},
    isPending: false,
    isSuccess: false,
    isIdle: true,
    isError: false,
    data: undefined,
    reset: () => {},
  }),
  ApiGetCallWithPagination: () => ({
    isSuccess: false,
    isPending: true,
    isFetching: false,
    isError: false,
    data: undefined,
  }),
  ApiGetCall: ({ url }) => {
    apiState.urls.push(url)
    if (url === '/api/listTenants') {
      return apiState.tenants
    }
    return apiState.details
  },
}))

// The selected tenant's cloud comes from the TenantSelector query cache, which this mocked ApiGetCall
// never fills; set it directly. getCloudPortalUrl itself is covered in tests/utils/cloud-portal-links.test.js.
vi.mock('../../../src/hooks/use-tenant-cloud', async (importOriginal) => {
  const actual = await importOriginal()
  const { getCloudPortalUrl } = await import('../../../src/utils/cloud-portal-links')
  return { ...actual, useCloudPortalUrl: () => (url) => getCloudPortalUrl(url, cloudState.cloud) }
})

vi.mock('next/router', () => ({
  useRouter: () => routerState.router,
}))

const result = (overrides = {}) => ({
  isLoading: false,
  isFetching: false,
  isError: false,
  isSuccess: true,
  error: null,
  data: undefined,
  refetch: vi.fn(),
  ...overrides,
})

const makeSettings = (overrides = {}) => ({
  currentTenant: null,
  currentTheme: { value: 'light', label: 'light' },
  paletteMode: 'light',
  direction: 'ltr',
  pinNav: true,
  handleUpdate: vi.fn(),
  handleReset: () => {},
  isCustom: false,
  ...overrides,
})

describe('CippTenantSelector portal links by cloud', () => {
  beforeEach(() => {
    apiState.tenants = result({ data: tenantsContosoFabrikam })
    apiState.details = result({ data: { displayName: 'Contoso' } })
    apiState.urls = []
    routerState.router = {
      isReady: true,
      pathname: '/',
      query: { tenantFilter: 'contoso.com' },
      replace: vi.fn(),
      push: vi.fn(),
      events: { on: () => {}, off: () => {}, emit: () => {} },
    }
  })

  const openPortals = async (cloud) => {
    cloudState.cloud = cloud
    const user = userEvent.setup()
    renderWithProviders(<CippTenantSelector tenantButton />, {
      settings: makeSettings({ currentTenant: 'contoso.com' }),
    })
    const infoButton = screen.getByRole('button', { name: 'tenantOffCanvas' })
    await waitFor(() => expect(infoButton).toBeEnabled())
    await user.click(infoButton)
    await waitFor(() => expect(screen.getByText('Manage Tenant')).toBeInTheDocument())
  }
  // Portal actions open through window.open when clicked.
  const hrefOf = async (label) => {
    const open = vi.spyOn(window, 'open').mockImplementation(() => null)
    await userEvent.setup().click(screen.getByText(label))
    await waitFor(() => expect(open).toHaveBeenCalled())
    const url = open.mock.calls.at(-1)[0]
    open.mockRestore()
    return url
  }

  it('shows every commercial portal link unchanged for a Commercial tenant', async () => {
    await openPortals('Commercial')
    expect(await hrefOf('M365 Admin Portal')).toBe(
      'https://admin.cloud.microsoft/?delegatedOrg=contoso.onmicrosoft.com'
    )
    expect(await hrefOf('Entra Portal')).toBe('https://entra.microsoft.com/contoso.com')
    expect(await hrefOf('Security Portal')).toBe(
      'https://security.microsoft.com/?tid=11111111-aaaa-bbbb-cccc-000000000001'
    )
    for (const label of ['Exchange Portal', 'Teams Portal', 'Purview Portal', 'Power BI Portal']) {
      expect(screen.getByText(label)).toBeInTheDocument()
    }
  })

  it('points a GCC High tenant at government portals and leaves out the ones without one', async () => {
    await openPortals('USGovHigh')
    expect(await hrefOf('Entra Portal')).toBe('https://entra.microsoft.us/contoso.com')
    expect(await hrefOf('Azure Portal')).toBe('https://portal.azure.us/contoso.com')
    expect(await hrefOf('Intune Portal')).toBe('https://intune.microsoft.us/contoso.com')
    expect(await hrefOf('Security Portal')).toBe(
      'https://security.microsoft.us/?tid=11111111-aaaa-bbbb-cccc-000000000001'
    )
    expect(await hrefOf('Purview Portal')).toBe(
      'https://purview.microsoft.us/?tid=11111111-aaaa-bbbb-cccc-000000000001'
    )
    for (const label of ['M365 Admin Portal', 'Exchange Portal', 'Teams Portal', 'Power BI Portal']) {
      expect(screen.queryByText(label)).not.toBeInTheDocument()
    }
    expect(screen.getByText('Manage Tenant')).toBeInTheDocument()
  })
})

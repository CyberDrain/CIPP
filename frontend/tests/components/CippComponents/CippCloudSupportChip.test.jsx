import { describe, it, expect } from 'vitest'
import { render, screen, renderHook } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { SettingsContext } from '../../../src/contexts/settings-context'
import { CippCloudSupportChip } from '../../../src/components/CippComponents/CippCloudSupportChip'
import { useTenantCloudEnvironment } from '../../../src/hooks/use-tenant-cloud'

// redanthrax/CIPP#4: the standards/baseline pickers flag items a government cloud does not support,
// but only for an estate that has a tenant in that cloud. The cloud comes from the tenant list the
// tenant selector cached (query key TenantSelector); nothing is fetched for it.
const commercialTenants = [
  { defaultDomainName: 'AllTenants', customerId: 'AllTenants' },
  {
    defaultDomainName: 'contoso.com',
    customerId: 'c1',
    cloudEnvironment: 'Commercial',
  },
]
const mixedTenants = [
  ...commercialTenants,
  {
    defaultDomainName: 'gov.us',
    customerId: 'g1',
    cloudEnvironment: 'USGovHigh',
  },
]

const wrapperFor = (tenants, currentTenant = 'contoso.com') => {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })
  if (tenants) client.setQueryData(['TenantSelector'], tenants)
  const Wrapper = ({ children }) => (
    <QueryClientProvider client={client}>
      <SettingsContext.Provider value={{ currentTenant }}>
        {children}
      </SettingsContext.Provider>
    </QueryClientProvider>
  )
  return Wrapper
}

describe('CippCloudSupportChip', () => {
  it('renders nothing for a commercial-only estate', () => {
    const { container } = render(
      <CippCloudSupportChip type="standards" name="TeamsGuestAccess" />,
      {
        wrapper: wrapperFor(commercialTenants),
      }
    )
    expect(container).toBeEmptyDOMElement()
  })

  it('renders nothing before the tenant list is cached', () => {
    const { container } = render(
      <CippCloudSupportChip type="standards" name="TeamsGuestAccess" />,
      {
        wrapper: wrapperFor(undefined),
      }
    )
    expect(container).toBeEmptyDOMElement()
  })

  it('flags a listed standard when the estate has a GCC High tenant', () => {
    render(<CippCloudSupportChip type="standards" name="TeamsGuestAccess" />, {
      wrapper: wrapperFor(mixedTenants),
    })
    expect(screen.getByText('Not supported in GCC High')).toBeInTheDocument()
  })

  it('does not flag a standard the matrix does not list', () => {
    const { container } = render(
      <CippCloudSupportChip type="standards" name="AuditLog" />,
      {
        wrapper: wrapperFor(mixedTenants),
      }
    )
    expect(container).toBeEmptyDOMElement()
  })
})

describe('useTenantCloudEnvironment', () => {
  it('reads the selected tenant cloud from the cached tenant list', () => {
    expect(
      renderHook(() => useTenantCloudEnvironment(), {
        wrapper: wrapperFor(mixedTenants, 'gov.us'),
      }).result.current
    ).toEqual('USGovHigh')
    expect(
      renderHook(() => useTenantCloudEnvironment(), {
        wrapper: wrapperFor(mixedTenants),
      }).result.current
    ).toEqual('Commercial')
    expect(
      renderHook(() => useTenantCloudEnvironment(), {
        wrapper: wrapperFor(mixedTenants, 'AllTenants'),
      }).result.current
    ).toBeUndefined()
    expect(
      renderHook(() => useTenantCloudEnvironment(), {
        wrapper: wrapperFor(undefined, 'gov.us'),
      }).result.current
    ).toBeUndefined()
  })
})

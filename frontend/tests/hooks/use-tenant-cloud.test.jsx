import { describe, it, expect, vi, afterEach } from 'vitest'
import { act, renderHook, waitFor } from '@testing-library/react'
import {
  QueryClient,
  QueryClientProvider,
  useQuery,
} from '@tanstack/react-query'
import { SettingsContext } from '../../src/contexts/settings-context'
import {
  useCloudPortalUrl,
  useGovernmentClouds,
  useTenantCloudEnvironment,
  useTenantList,
} from '../../src/hooks/use-tenant-cloud'

// redanthrax/CIPP#4: the hook reads the tenant list the tenant selector cached under the query key
// TenantSelector. It must never fetch, never register a query observer without a queryFn on that
// query (that logged "No queryFn was passed" and could break the selector's refetch), and must
// follow the list when it loads or changes.
const commercial = [
  { defaultDomainName: 'AllTenants', customerId: 'AllTenants' },
  {
    defaultDomainName: 'contoso.com',
    customerId: 'c1',
    cloudEnvironment: 'Commercial',
  },
]
const mixed = [
  ...commercial,
  {
    defaultDomainName: 'gov.us',
    customerId: 'g1',
    cloudEnvironment: 'USGovHigh',
  },
]

const setup = (currentTenant) => {
  const client = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  })
  const wrapper = ({ children }) => (
    <QueryClientProvider client={client}>
      <SettingsContext.Provider value={{ currentTenant }}>
        {children}
      </SettingsContext.Provider>
    </QueryClientProvider>
  )
  return { client, wrapper }
}

const tenantQuery = (client) =>
  client.getQueryCache().find({ queryKey: ['TenantSelector'], exact: true })

afterEach(() => {
  vi.restoreAllMocks()
})

describe('useTenantList', () => {
  it('creates no query and no observer before the selector loads the list', () => {
    const error = vi.spyOn(console, 'error').mockImplementation(() => {})
    const { client, wrapper } = setup('gov.us')
    const { result } = renderHook(() => useTenantCloudEnvironment(), {
      wrapper,
    })
    expect(result.current).toBeUndefined()
    expect(tenantQuery(client)).toBeUndefined()
    expect(error).not.toHaveBeenCalledWith(
      expect.stringContaining('No queryFn')
    )
  })

  it('updates when the list is cached and when it changes', () => {
    const { client, wrapper } = setup('gov.us')
    const { result } = renderHook(() => useTenantCloudEnvironment(), {
      wrapper,
    })
    expect(result.current).toBeUndefined()

    act(() => client.setQueryData(['TenantSelector'], mixed))
    expect(result.current).toBe('USGovHigh')

    act(() => client.setQueryData(['TenantSelector'], commercial))
    expect(result.current).toBeUndefined()
  })

  it('does not fetch, add an observer or block the selector refetching', async () => {
    const queryFn = vi.fn().mockResolvedValueOnce(commercial).mockResolvedValue(mixed)
    const { client, wrapper } = setup('gov.us')
    const { result } = renderHook(
      () => {
        // the tenant selector's own query
        const selector = useQuery({ queryKey: ['TenantSelector'], queryFn })
        return {
          selector,
          cloud: useTenantCloudEnvironment(),
          govClouds: useGovernmentClouds(),
          list: useTenantList(),
        }
      },
      { wrapper }
    )

    await waitFor(() => expect(result.current.list).toBe(commercial))
    expect(queryFn).toHaveBeenCalledTimes(1)
    expect(tenantQuery(client).getObserversCount()).toBe(1)
    expect(result.current.cloud).toBeUndefined()
    expect(result.current.govClouds).toEqual([])

    await act(() =>
      client.invalidateQueries({ queryKey: ['TenantSelector'] })
    )
    await waitFor(() => expect(result.current.cloud).toBe('USGovHigh'))
    expect(queryFn).toHaveBeenCalledTimes(2)
    expect(result.current.govClouds).toEqual(['USGovHigh'])
    expect(tenantQuery(client).getObserversCount()).toBe(1)
  })

  it('returns Commercial for a commercial tenant and nothing for AllTenants', () => {
    const { client, wrapper } = setup('contoso.com')
    client.setQueryData(['TenantSelector'], mixed)
    expect(
      renderHook(() => useTenantCloudEnvironment(), { wrapper }).result.current
    ).toBe('Commercial')
    expect(
      renderHook(() => useTenantCloudEnvironment('AllTenants'), { wrapper })
        .result.current
    ).toBeUndefined()
  })

  it('ignores other queries', () => {
    const { client, wrapper } = setup('gov.us')
    client.setQueryData(['TenantSelector'], mixed)
    let renders = 0
    renderHook(
      () => {
        renders += 1
        return useTenantCloudEnvironment()
      },
      { wrapper }
    )
    const before = renders
    act(() => client.setQueryData(['TenantSelector-other'], commercial))
    act(() => client.setQueryData(['ListUsers'], []))
    expect(renders).toBe(before)
  })
})

describe('useCloudPortalUrl', () => {
  const entra = 'https://entra.microsoft.com/x/#view/Y'
  it.each([
    ['a Commercial tenant', 'contoso.com'],
    ['AllTenants', 'AllTenants'],
  ])('returns portal links unchanged for %s', (_name, tenant) => {
    const { client, wrapper } = setup(tenant)
    client.setQueryData(['TenantSelector'], mixed)
    const { result } = renderHook(() => useCloudPortalUrl(), { wrapper })
    expect(result.current(entra)).toBe(entra)
  })

  it('returns portal links unchanged before the tenant list is cached', () => {
    const { wrapper } = setup('gov.us')
    const { result } = renderHook(() => useCloudPortalUrl(), { wrapper })
    expect(result.current(entra)).toBe(entra)
  })

  it('points portal links at the government portal for the current or a given GCC High tenant', () => {
    const { client, wrapper } = setup('gov.us')
    client.setQueryData(['TenantSelector'], mixed)
    const { result } = renderHook(() => useCloudPortalUrl(), { wrapper })
    expect(result.current(entra)).toBe('https://entra.microsoft.us/x/#view/Y')
    const given = renderHook(() => useCloudPortalUrl('contoso.com'), { wrapper })
    expect(given.result.current(entra)).toBe(entra)
  })
})

import React from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { render } from '@testing-library/react'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { SettingsContext } from '../../../src/contexts/settings-context'

vi.mock('../../../src/api/ApiCall', async () => (await import('../../mocks/api-call')).apiCallMock())
import { api, getResult } from '../../mocks/api-call'
import { ApiGetCall } from '../../../src/api/ApiCall'
import CippAppRegistrationPermissions from '../../../src/components/CippComponents/CippAppRegistrationPermissions'

// redanthrax/CIPP#4: an app in a government tenant has its permission ids resolved against that tenant's
// service principals (they differ from the partner cloud's). For any other tenant the requests and their
// cache keys are exactly the pre-change ones.
const tenants = [
  { defaultDomainName: 'AllTenants', customerId: 'AllTenants' },
  { defaultDomainName: 'contoso.com', customerId: 'c1', cloudEnvironment: 'Commercial' },
  { defaultDomainName: 'gov.us', customerId: 'g1', cloudEnvironment: 'USGovHigh' },
]
const GRAPH = '00000003-0000-0000-c000-000000000000'
const requiredResourceAccess = [
  { resourceAppId: GRAPH, resourceAccess: [{ id: 'role-1', type: 'Role' }, { id: 'scope-1', type: 'Scope' }] },
]
const listResult = getResult({ data: { Results: [{ appId: GRAPH, id: 'sp-graph', displayName: 'Microsoft Graph' }] } })
const spResult = getResult({ data: { Results: { displayName: 'Microsoft Graph', appRoles: [], publishedPermissionScopes: [] } } })

const renderFor = (tenantFilter, props = {}) => {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } })
  client.setQueryData(['TenantSelector'], tenants)
  return render(
    <QueryClientProvider client={client}>
      <SettingsContext.Provider value={{ currentTenant: 'gov.us' }}>
        <CippAppRegistrationPermissions
          requiredResourceAccess={requiredResourceAccess}
          tenantFilter={tenantFilter}
          {...props}
        />
      </SettingsContext.Provider>
    </QueryClientProvider>
  )
}

const calls = () => ApiGetCall.mock.calls.map(([opts]) => ({ data: opts.data, queryKey: opts.queryKey }))

describe('CippAppRegistrationPermissions tenant for permission names', () => {
  beforeEach(() => {
    ApiGetCall.mockClear()
    api.get = (opts) => (opts.data?.Select ? listResult : spResult)
  })

  it.each([
    ['a Commercial tenant', 'contoso.com'],
    ['AllTenants', 'AllTenants'],
    ['an unknown tenant', 'unknown.com'],
    ['no tenantFilter (current tenant is not used)', undefined],
  ])('sends the partner requests unchanged for %s', (_name, tenantFilter) => {
    renderFor(tenantFilter)
    const all = calls()
    expect(all).toContainEqual({
      data: { Select: 'appId,displayName,id' },
      queryKey: 'execServicePrincipalList-app-registration-permissions',
    })
    expect(all).toContainEqual({
      data: { Id: 'sp-graph' },
      queryKey: `execSP-appreg-perms-sp-graph-${GRAPH}`,
    })
    expect(all.every((c) => !('tenantFilter' in c.data) && !('GovernmentTenantFilter' in c.data))).toBe(true)
  })

  it('reads the service principals of a government tenant from that tenant', () => {
    renderFor('gov.us')
    const all = calls()
    expect(all).toContainEqual({
      data: { Select: 'appId,displayName,id', GovernmentTenantFilter: 'gov.us' },
      queryKey: 'execServicePrincipalList-app-registration-permissions-gov.us',
    })
    expect(all).toContainEqual({
      data: { Id: 'sp-graph', GovernmentTenantFilter: 'gov.us' },
      queryKey: `execSP-appreg-perms-sp-graph-${GRAPH}-gov.us`,
    })
  })
})

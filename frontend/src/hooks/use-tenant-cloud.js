import { useCallback, useSyncExternalStore } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { useSettings } from './use-settings'
import {
  findTenantCloud,
  getGovernmentClouds,
} from '../utils/cloud-feature-support'
import { getCloudPortalUrl } from '../utils/cloud-portal-links'

const TENANT_LIST_KEY = ['TenantSelector']

const isTenantListQuery = (query) =>
  query?.queryKey?.length === 1 && query.queryKey[0] === TENANT_LIST_KEY[0]

// Reads the tenant list the tenant selector already loaded (query key TenantSelector) straight from
// the query cache. It registers no query observer, so it never fetches, never adds a queryFn-less
// observer to the selector's query (which would break its refetch/invalidate) and does not change
// how long that query is kept. It re-renders when that query's data changes. Until the list is in
// the cache the cloud is unknown and nothing is gated (redanthrax/CIPP#4).
export const useTenantList = () => {
  const queryClient = useQueryClient()
  const subscribe = useCallback(
    (onChange) =>
      queryClient.getQueryCache().subscribe((event) => {
        if (isTenantListQuery(event?.query)) onChange()
      }),
    [queryClient]
  )
  const getSnapshot = useCallback(
    () => queryClient.getQueryData(TENANT_LIST_KEY),
    [queryClient]
  )
  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot)
}

// The selected tenant's cloud (Commercial, USGovHigh, USGovDoD), or undefined for AllTenants,
// an unknown tenant or before the tenant list has loaded.
export const useTenantCloudEnvironment = (tenant) => {
  const settings = useSettings()
  const tenants = useTenantList()
  return findTenantCloud(tenants, tenant ?? settings?.currentTenant)
}

// The government clouds among the tenants the user can see ([] for a commercial-only estate).
export const useGovernmentClouds = () => getGovernmentClouds(useTenantList())

// A `(url) => url` mapper that points Microsoft admin portal links at the tenant's government portal,
// or returns undefined when that portal has none (redanthrax/CIPP#4). For Commercial, AllTenants or an
// unknown cloud it returns every URL unchanged.
export const useCloudPortalUrl = (tenant) => {
  const cloud = useTenantCloudEnvironment(tenant)
  return useCallback((url) => getCloudPortalUrl(url, cloud), [cloud])
}

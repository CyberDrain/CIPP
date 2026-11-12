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

// Reads the cache without an observer: a queryFn-less observer would break the selector's refetch.
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

// undefined for AllTenants, an unknown tenant or before the tenant list has loaded.
export const useTenantCloudEnvironment = (tenant) => {
  const settings = useSettings()
  const tenants = useTenantList()
  return findTenantCloud(tenants, tenant ?? settings?.currentTenant)
}

export const useGovernmentClouds = () => getGovernmentClouds(useTenantList())

// The mapper returns undefined for a portal with no government equivalent.
export const useCloudPortalUrl = (tenant) => {
  const cloud = useTenantCloudEnvironment(tenant)
  return useCallback((url) => getCloudPortalUrl(url, cloud), [cloud])
}

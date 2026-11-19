// cloudFeatureSupport.json is shared with backend/Config; CloudFeatureSupportSync.Tests.ps1 keeps them identical.
import matrix from '../data/cloudFeatureSupport.json'
import { getCloudEnvironment } from './cloud-environments'
import { getCloudPortalUrl } from './cloud-portal-links'

const SECTIONS = [
  'pages',
  'actions',
  'standards',
  'baselineStandards',
  'alerts',
  'tests',
  'cacheTypes',
  'timers',
]

const keyOf = (entry) => entry.name ?? entry.path ?? entry.url

const index = Object.fromEntries(
  SECTIONS.map((section) => [
    section,
    new Map((matrix[section] ?? []).map((entry) => [keyOf(entry), entry])),
  ])
)

export const getUnsupportedClouds = (type, name) =>
  index[type]?.get(name)?.unsupportedClouds ?? []

export const getCloudSupportEntry = (type, name) => {
  const entry = index[type]?.get(name)
  if (!entry) return undefined
  return { ...entry, ...(matrix.sources?.[entry.source] ?? {}) }
}

export const isCloudSupported = (type, name, cloud) =>
  !cloud ||
  cloud === 'Commercial' ||
  !getUnsupportedClouds(type, name).includes(cloud)

export const getUnsupportedPage = (pathname, cloud) => {
  if (!pathname || !cloud || cloud === 'Commercial') return undefined
  const path = pathname.length > 1 ? pathname.replace(/\/+$/, '') : pathname
  for (const [pagePath, entry] of index.pages) {
    if (
      (path === pagePath ||
        (!entry.exact && path.startsWith(`${pagePath}/`))) &&
      entry.unsupportedClouds.includes(cloud)
    ) {
      return getCloudSupportEntry('pages', pagePath)
    }
  }
  return undefined
}

export const getCloudNavFallback = (path, cloud) => {
  if (!path || !cloud || cloud === 'Commercial') return undefined
  const fallback = index.pages.get(path)?.navFallback
  return fallback && !getUnsupportedPage(fallback, cloud) ? fallback : undefined
}

// Returns the same array when nothing is removed.
export const filterCloudSupportedTabs = (tabs, cloud) => {
  if (!Array.isArray(tabs) || !cloud || cloud === 'Commercial') return tabs
  const filtered = tabs.filter((tab) => !getUnsupportedPage(tab?.path, cloud))
  return filtered.length === tabs.length ? tabs : filtered
}

// Items the matrix does not list are returned as the same object.
export const withCloudSupport = (items) =>
  items.map((item) => {
    let next = item
    if (item.items?.length) {
      const children = withCloudSupport(item.items)
      if (children.some((child, i) => child !== item.items[i]))
        next = { ...next, items: children }
    }
    const clouds = item.path ? getUnsupportedClouds('pages', item.path) : []
    if (clouds.length > 0) {
      next = {
        ...next,
        unsupportedClouds: [
          ...new Set([...(item.unsupportedClouds ?? []), ...clouds]),
        ],
      }
    }
    return next
  })

// Returns the same array when nothing changes.
export const filterCloudSupportedActions = (actions, cloud) => {
  if (!Array.isArray(actions) || !cloud || cloud === 'Commercial')
    return actions
  let changed = false
  const filtered = []
  for (const action of actions) {
    const url =
      typeof action?.url === 'string' ? action.url.split('?')[0] : undefined
    if (url && !isCloudSupported('actions', url, cloud)) {
      changed = true
      continue
    }
    if (typeof action?.link === 'string') {
      const link = getCloudPortalUrl(action.link, cloud)
      if (link === undefined) {
        changed = true
        continue
      }
      if (link !== action.link) {
        changed = true
        filtered.push({ ...action, link })
        continue
      }
    }
    filtered.push(action)
  }
  return changed ? filtered : actions
}

export const getGovernmentClouds = (tenants) =>
  Array.isArray(tenants)
    ? [
        ...new Set(
          tenants
            .map((tenant) => getCloudEnvironment(tenant?.cloudEnvironment))
            .filter((cloud) => cloud?.isGovernment)
            .map((cloud) => cloud.value)
        ),
      ]
    : []

// Same lookup order as the tenant selector.
export const findTenantCloud = (tenants, tenant) => {
  if (!Array.isArray(tenants) || !tenant || tenant === 'AllTenants')
    return undefined
  const match =
    tenants.find(({ defaultDomainName }) => defaultDomainName === tenant) ||
    tenants.find(({ customerId }) => customerId === tenant) ||
    tenants.find(({ initialDomainName }) => initialDomainName === tenant)
  return getCloudEnvironment(match?.cloudEnvironment)?.value
}

export const cloudLabel = (cloud) => getCloudEnvironment(cloud)?.label ?? cloud

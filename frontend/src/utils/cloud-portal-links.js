// Host map and its sources: `portalHosts` in src/data/cloudFeatureSupport.json.
import matrix from '../data/cloudFeatureSupport.json'

const PORTAL_URL = /^https:\/\/([^/?#:]+)/i

// undefined when the portal has no documented government equivalent.
export const getCloudPortalUrl = (url, cloud) => {
  const hosts =
    cloud && cloud !== 'Commercial' && cloud !== '$comment' ? matrix.portalHosts?.[cloud] : undefined
  if (!hosts || typeof url !== 'string') return url
  const match = PORTAL_URL.exec(url)
  const host = match?.[1].toLowerCase()
  if (!host || !Object.hasOwn(hosts, host)) return url
  return hosts[host] ? `https://${hosts[host]}${url.slice(match[0].length)}` : undefined
}

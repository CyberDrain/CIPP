// Microsoft admin portal links for a tenant's cloud (redanthrax/CIPP#4). A government tenant cannot be
// managed from the commercial portals, so a link to one is pointed at the government portal when
// Microsoft documents it, and dropped (undefined) when it does not. Only the host changes; the rest of
// the URL is kept. The host map, with its sources, is `portalHosts` in src/data/cloudFeatureSupport.json
// (the backend reads the same file). Commercial, AllTenants and an unknown cloud get the URL back
// unchanged (the same string), and so does any URL whose host is not a commercial portal listed there.
import matrix from '../data/cloudFeatureSupport.json'

const PORTAL_URL = /^https:\/\/([^/?#:]+)/i

// The link for `cloud`: unchanged for Commercial/unknown clouds and non-portal URLs, the government
// portal's URL when there is one, undefined when the portal has no documented government equivalent.
export const getCloudPortalUrl = (url, cloud) => {
  const hosts =
    cloud && cloud !== 'Commercial' && cloud !== '$comment' ? matrix.portalHosts?.[cloud] : undefined
  if (!hosts || typeof url !== 'string') return url
  const match = PORTAL_URL.exec(url)
  const host = match?.[1].toLowerCase()
  if (!host || !Object.hasOwn(hosts, host)) return url
  return hosts[host] ? `https://${hosts[host]}${url.slice(match[0].length)}` : undefined
}

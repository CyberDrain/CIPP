import { describe, it, expect } from 'vitest'
import { getCloudPortalUrl } from '../../src/utils/cloud-portal-links'
import { filterCloudSupportedActions } from '../../src/utils/cloud-feature-support'

// redanthrax/CIPP#4: portal links follow a government tenant's cloud; everything else is untouched.
const links = [
  'https://admin.cloud.microsoft/?delegatedOrg=contoso.onmicrosoft.com',
  'https://admin.cloud.microsoft/exchange?delegatedOrg=contoso.onmicrosoft.com',
  'https://entra.microsoft.com/contoso.com/#view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/Overview/groupId/1',
  'https://admin.teams.microsoft.com/?delegatedOrg=contoso.onmicrosoft.com',
  'https://portal.azure.com/contoso.com',
  'https://intune.microsoft.com/contoso.com/#view/Microsoft_Intune_Devices/DeviceSettingsMenuBlade/~/overview/mdmDeviceId/[id]',
  'https://security.microsoft.com/?tid=c1',
  'https://purview.microsoft.com/?tid=c1',
  'https://admin.powerplatform.microsoft.com/account/login/c1',
  'https://app.powerbi.com/admin-portal?ctid=c1',
  '/tenant/manage/edit?tenantFilter=contoso.com',
  '/api/ListSharePointAdminUrl?tenantFilter=contoso.com',
  'https://contoso-admin.sharepoint.com/',
  '[consentUrl]',
]

describe('getCloudPortalUrl', () => {
  it.each([['Commercial'], [undefined], [null], ['AllTenants'], ['$comment'], ['USGovModerate']])(
    'returns every URL unchanged for cloud %s',
    (cloud) => {
      for (const url of links) expect(getCloudPortalUrl(url, cloud)).toBe(url)
    }
  )

  it('points documented portals at GCC High and DoD hosts, keeping the rest of the URL', () => {
    expect(getCloudPortalUrl('https://entra.microsoft.com/gov.us/#view/X', 'USGovHigh')).toBe(
      'https://entra.microsoft.us/gov.us/#view/X'
    )
    expect(getCloudPortalUrl('https://portal.azure.com/gov.us', 'USGovDoD')).toBe('https://portal.azure.us/gov.us')
    expect(getCloudPortalUrl('https://intune.microsoft.com/gov.us/', 'USGovHigh')).toBe('https://intune.microsoft.us/gov.us/')
    expect(getCloudPortalUrl('https://endpoint.microsoft.com/gov.us/#blade/X', 'USGovDoD')).toBe(
      'https://intune.microsoft.us/gov.us/#blade/X'
    )
    expect(getCloudPortalUrl('https://security.microsoft.com/?tid=g1', 'USGovHigh')).toBe('https://security.microsoft.us/?tid=g1')
    expect(getCloudPortalUrl('https://security.microsoft.com/?tid=g1', 'USGovDoD')).toBe('https://security.apps.mil/?tid=g1')
    expect(getCloudPortalUrl('https://admin.powerplatform.microsoft.com/account/login/g1', 'USGovHigh')).toBe(
      'https://high.admin.powerplatform.microsoft.us/account/login/g1'
    )
    expect(getCloudPortalUrl('https://admin.powerplatform.microsoft.com/account/login/g1', 'USGovDoD')).toBe(
      'https://admin.appsplatform.us/account/login/g1'
    )
    expect(getCloudPortalUrl('https://purview.microsoft.com/?tid=g1', 'USGovHigh')).toBe('https://purview.microsoft.us/?tid=g1')
    expect(getCloudPortalUrl('https://purview.microsoft.com/?tid=g1', 'USGovDoD')).toBe('https://purview.apps.mil/?tid=g1')
  })

  it('drops portals with no documented government URL', () => {
    for (const url of [links[0], links[1], links[3], links[9]]) {
      expect(getCloudPortalUrl(url, 'USGovHigh')).toBeUndefined()
      expect(getCloudPortalUrl(url, 'USGovDoD')).toBeUndefined()
    }
  })

  it('leaves relative, placeholder and other-host URLs alone for a government cloud', () => {
    for (const url of links.slice(10)) expect(getCloudPortalUrl(url, 'USGovHigh')).toBe(url)
    expect(getCloudPortalUrl('https://entra.microsoft.com.evil.example/x', 'USGovHigh')).toBe(
      'https://entra.microsoft.com.evil.example/x'
    )
  })
})

describe('filterCloudSupportedActions portal links', () => {
  const actions = [
    { label: 'View in Entra', link: 'https://entra.microsoft.com/[Tenant]/#view/X/[id]' },
    { label: 'Teams', link: 'https://admin.teams.microsoft.com/?delegatedOrg=x' },
    { label: 'Internal', link: '/identity/administration/users/user?userId=[id]' },
    { label: 'Edit', url: '/api/EditUser' },
  ]

  it('returns the same array for Commercial and an unknown cloud', () => {
    expect(filterCloudSupportedActions(actions, 'Commercial')).toBe(actions)
    expect(filterCloudSupportedActions(actions, undefined)).toBe(actions)
  })

  it('re-points and drops portal link actions for a government tenant', () => {
    const result = filterCloudSupportedActions(actions, 'USGovHigh')
    expect(result.map((a) => a.label)).toEqual(['View in Entra', 'Internal', 'Edit'])
    expect(result[0].link).toBe('https://entra.microsoft.us/[Tenant]/#view/X/[id]')
    expect(result[1]).toBe(actions[2])
    expect(actions[0].link).toBe('https://entra.microsoft.com/[Tenant]/#view/X/[id]')
  })

  it('returns the same array for a government tenant when no action changes', () => {
    const plain = [actions[2], actions[3]]
    expect(filterCloudSupportedActions(plain, 'USGovHigh')).toBe(plain)
  })
})

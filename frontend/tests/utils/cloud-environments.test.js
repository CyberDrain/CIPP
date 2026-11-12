import {
  cloudEnvironmentOptions,
  getCloudEnvironment,
  getDirectTenantScope,
} from '../../src/utils/cloud-environments'

// redanthrax/CIPP#2: the consent flow's hosts come from a fixed map keyed on the exact cloud values.
describe('cloud-environments', () => {
  it.each([
    ['Commercial', 'https://login.microsoftonline.com', 'https://graph.microsoft.com', false],
    ['USGovHigh', 'https://login.microsoftonline.us', 'https://graph.microsoft.us', true],
    ['USGovDoD', 'https://login.microsoftonline.us', 'https://dod-graph.microsoft.us', true],
  ])('maps %s to literal hosts', (value, authority, graphUrl, isGovernment) => {
    expect(getCloudEnvironment(value)).toMatchObject({ value, authority, graphUrl, isGovernment })
  })

  it.each([['usgovhigh'], [''], [undefined], [null], ['constructor'], ['__proto__'], ['GCCHigh']])(
    'returns nothing for %s',
    (value) => {
      expect(getCloudEnvironment(value)).toBeUndefined()
      expect(() => getDirectTenantScope(value)).toThrow()
    }
  )

  it('keeps the commercial direct-tenant scope identical to the pre-#2 string', () => {
    expect(getDirectTenantScope('Commercial')).toBe(
      'https://graph.microsoft.com/DelegatedPermissionGrant.ReadWrite.All https://graph.microsoft.com/Directory.ReadWrite.All https://graph.microsoft.com/AppRoleAssignment.ReadWrite.All offline_access profile openid'
    )
  })

  it.each([
    ['USGovHigh', 'https://graph.microsoft.us/'],
    ['USGovDoD', 'https://dod-graph.microsoft.us/'],
  ])('puts every %s Graph scope on its own host', (value, prefix) => {
    const scopes = getDirectTenantScope(value).split(' ')
    expect(scopes.filter((scope) => scope.startsWith('https://'))).toHaveLength(3)
    scopes
      .filter((scope) => scope.startsWith('https://'))
      .forEach((scope) => expect(scope.startsWith(prefix)).toBe(true))
    expect(getDirectTenantScope(value)).not.toContain('microsoft.com')
  })

  it('cannot be modified at runtime', () => {
    expect(() => {
      getCloudEnvironment('USGovHigh').authority = 'https://evil.example'
    }).toThrow()
    expect(cloudEnvironmentOptions.map((option) => option.value)).toEqual([
      'Commercial',
      'USGovHigh',
      'USGovDoD',
    ])
  })
})

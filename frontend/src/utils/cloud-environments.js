// Fixed sign-in and Graph hosts per Microsoft cloud (redanthrax/CIPP#2). Mirrors the backend's
// Get-CIPPCloudEndpoint: keyed on the exact cloudEnvironment values, every host is a literal, and an
// unknown value gets nothing back - callers must refuse rather than fall back to Commercial.
const CLOUD_ENVIRONMENTS = Object.freeze({
  Commercial: Object.freeze({
    value: 'Commercial',
    label: 'Commercial / GCC',
    description: 'Commercial Microsoft 365, including GCC (Moderate).',
    isGovernment: false,
    authority: 'https://login.microsoftonline.com',
    graphUrl: 'https://graph.microsoft.com',
  }),
  USGovHigh: Object.freeze({
    value: 'USGovHigh',
    label: 'GCC High',
    description: 'Microsoft 365 GCC High (Azure Government). Needs the Azure Government app.',
    isGovernment: true,
    authority: 'https://login.microsoftonline.us',
    graphUrl: 'https://graph.microsoft.us',
  }),
  USGovDoD: Object.freeze({
    value: 'USGovDoD',
    label: 'DoD',
    description: 'Microsoft 365 DoD (Azure Government). Needs the Azure Government app.',
    isGovernment: true,
    authority: 'https://login.microsoftonline.us',
    graphUrl: 'https://dod-graph.microsoft.us',
  }),
})

export const cloudEnvironmentOptions = Object.values(CLOUD_ENVIRONMENTS)

// Exact, case-sensitive lookup; undefined for anything else.
export const getCloudEnvironment = (value) =>
  typeof value === 'string' && Object.prototype.hasOwnProperty.call(CLOUD_ENVIRONMENTS, value)
    ? CLOUD_ENVIRONMENTS[value]
    : undefined

// The delegated scopes the direct-tenant consent asks for, on the cloud's Graph host.
const DIRECT_TENANT_GRAPH_PERMISSIONS = [
  'DelegatedPermissionGrant.ReadWrite.All',
  'Directory.ReadWrite.All',
  'AppRoleAssignment.ReadWrite.All',
]

export const getDirectTenantScope = (value) => {
  const cloud = getCloudEnvironment(value)
  if (!cloud) throw new Error('Unknown cloud environment')
  return [
    ...DIRECT_TENANT_GRAPH_PERMISSIONS.map((permission) => `${cloud.graphUrl}/${permission}`),
    'offline_access',
    'profile',
    'openid',
  ].join(' ')
}

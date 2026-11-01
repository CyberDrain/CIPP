import React from 'react'
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { renderWithProviders, settingsWith } from '../test-utils'
import Page from '../../src/pages/endpoint/MEM/list-scripts/index'
import { CippTablePage } from '../../src/components/CippComponents/CippTablePage'

vi.mock('../../src/layouts/index', () => ({
  Layout: ({ children }) => children,
}))
vi.mock('../../src/components/CippComponents/CippCodeBlock', () => ({
  CippCodeBlock: () => null,
}))
vi.mock('../../src/components/CippComponents/CippTablePage', () => ({
  CippTablePage: vi.fn(() => null),
}))
vi.mock('../../src/api/ApiCall', () => ({
  ApiGetCall: vi.fn(() => ({
    isSuccess: false,
    isFetching: false,
    data: undefined,
  })),
  ApiPostCall: vi.fn(() => ({ mutate: vi.fn() })),
}))

const scripts = [
  { id: 'windows-1', scriptType: 'Windows', Tenant: 'alpha.example.com' },
  { id: 'mac-1', scriptType: 'MacOS', Tenant: 'beta.example.com' },
]

function getAction(label, tenant) {
  renderWithProviders(<Page />, {
    settings: settingsWith({ currentTenant: tenant }),
  })
  const action = CippTablePage.mock.calls
    .at(-1)[0]
    .actions.find((item) => item.label === label)
  expect(action).toBeDefined()
  return action
}

// A bulk selection reaches customDataformatter as an array of rows. CippApiDialog only sends one
// request per row when the formatter returns an array, so a single object built from row.id
// would send one request with ID undefined.
describe.each([
  ['Assign to All Users', 'allLicensedUsers'],
  ['Assign to All Devices', 'AllDevices'],
  ['Assign Globally (All Users / All Devices)', 'AllDevicesAndUsers'],
])('%s', (label, target) => {
  beforeEach(() => vi.clearAllMocks())

  it('returns one payload per selected script, each with its own tenant', () => {
    const action = getAction(label, 'AllTenants')
    expect(
      action.customDataformatter(scripts, action, { assignmentMode: 'replace' })
    ).toEqual([
      {
        tenantFilter: 'alpha.example.com',
        ID: 'windows-1',
        Type: 'deviceManagementScripts',
        AssignTo: target,
        assignmentMode: 'replace',
      },
      {
        tenantFilter: 'beta.example.com',
        ID: 'mac-1',
        Type: 'deviceShellScripts',
        AssignTo: target,
        assignmentMode: 'replace',
      },
    ])
  })

  it('still returns a single payload for a single-row action', () => {
    const action = getAction(label, 'selected.example.com')
    expect(action.customDataformatter(scripts[1], action, {})).toEqual({
      tenantFilter: 'selected.example.com',
      ID: 'mac-1',
      Type: 'deviceShellScripts',
      AssignTo: target,
      assignmentMode: 'append',
    })
  })
})

describe('Assign to Custom Group', () => {
  beforeEach(() => vi.clearAllMocks())

  it('returns one payload per selected script with the chosen groups', () => {
    const action = getAction('Assign to Custom Group', 'selected.example.com')
    const formData = {
      groupTargets: [{ value: 'group-1', label: 'Group One' }],
      assignmentDirection: 'include',
    }
    const payloads = action.customDataformatter(scripts, action, formData)
    expect(payloads).toHaveLength(2)
    expect(
      payloads.map(({ ID, Type, tenantFilter }) => ({ ID, Type, tenantFilter }))
    ).toEqual([
      {
        ID: 'windows-1',
        Type: 'deviceManagementScripts',
        tenantFilter: 'selected.example.com',
      },
      {
        ID: 'mac-1',
        Type: 'deviceShellScripts',
        tenantFilter: 'selected.example.com',
      },
    ])
    for (const payload of payloads) {
      expect(payload).toMatchObject({
        GroupIds: ['group-1'],
        GroupNames: ['Group One'],
      })
    }
  })
})

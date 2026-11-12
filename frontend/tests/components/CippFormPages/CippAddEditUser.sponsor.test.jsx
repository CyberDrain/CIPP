import React, { useEffect } from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { waitFor, act } from '@testing-library/react'
import { useForm } from 'react-hook-form'
import { renderWithProviders } from '../../test-utils'
import { api, getResult } from '../../mocks/api-call'
import CippAddEditUser from '../../../src/components/CippFormPages/CippAddEditUser'

vi.mock('../../../src/api/ApiCall', async () =>
  (await import('../../mocks/api-call')).apiCallMock()
)
vi.mock(
  '../../../src/components/CippComponents/CippFormLicenseSelector',
  () => ({
    CippFormLicenseSelector: () => (
      <div data-testid="CippFormLicenseSelector" />
    ),
    default: () => <div data-testid="CippFormLicenseSelector" />,
  })
)
vi.mock('../../../src/components/CippComponents/CippFormUserSelector', () => ({
  CippFormUserSelector: () => <div data-testid="CippFormUserSelector" />,
  default: () => <div data-testid="CippFormUserSelector" />,
}))
vi.mock(
  '../../../src/components/CippComponents/CippFormDomainSelector',
  () => ({
    CippFormDomainSelector: () => <div data-testid="CippFormDomainSelector" />,
    default: () => <div data-testid="CippFormDomainSelector" />,
  })
)
vi.mock('../../../src/components/CippTable/CippDataTable', () => ({
  CippDataTable: () => <div data-testid="CippDataTable" />,
  default: () => <div data-testid="CippDataTable" />,
}))

const SPONSOR = {
  label: 'Jane Doe (jane@contoso.com)',
  value: 'jane@contoso.com',
}
const sponsorOn = [{ label: 'sponsor', value: 'sponsor' }]
const emptyGet = getResult({ data: [] })

let formApi = null
function Harness({ userAttributes }) {
  const formControl = useForm({ mode: 'onChange' })
  useEffect(() => {
    formApi = formControl
  }, [formControl])
  return (
    <CippAddEditUser
      formControl={formControl}
      formType="add"
      userSettingsDefaults={{ userAttributes }}
    />
  )
}

const selectTemplate = (template) =>
  act(() => {
    formApi.setValue('userTemplate', {
      label: template.templateName,
      value: template.GUID,
      addedFields: template,
    })
  })

describe('CippAddEditUser - sponsor from a user template', () => {
  beforeEach(() => {
    formApi = null
    api.get = emptyGet
  })

  it('fills Set Sponsor from the template when the sponsor attribute is on', async () => {
    renderWithProviders(<Harness userAttributes={sponsorOn} />)
    await waitFor(() => expect(formApi).not.toBeNull())

    await selectTemplate({
      GUID: 'template-a',
      templateName: 'Sales',
      setSponsor: SPONSOR,
    })

    await waitFor(() =>
      expect(formApi.getValues('setSponsor')).toEqual(SPONSOR)
    )
  })

  it('does not apply the template sponsor when the sponsor attribute is off', async () => {
    renderWithProviders(<Harness userAttributes={[]} />)
    await waitFor(() => expect(formApi).not.toBeNull())

    await selectTemplate({
      GUID: 'template-a',
      templateName: 'Sales',
      department: 'Sales',
      setSponsor: SPONSOR,
    })

    await waitFor(() => expect(formApi.getValues('department')).toBe('Sales'))
    expect(formApi.getValues('setSponsor')).toBeUndefined()
  })
})

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

const MANAGER = {
  label: 'Jane Doe (jane@contoso.com)',
  value: 'jane@contoso.com',
}
const emptyGet = getResult({ data: [] })

let formApi = null
function Harness() {
  const formControl = useForm({ mode: 'onChange' })
  useEffect(() => {
    formApi = formControl
  }, [formControl])
  return (
    <CippAddEditUser
      formControl={formControl}
      formType="add"
      userSettingsDefaults={{ userAttributes: [] }}
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

describe('CippAddEditUser - manager from a user template', () => {
  beforeEach(() => {
    formApi = null
    api.get = emptyGet
  })

  it('fills Set Manager from the template', async () => {
    renderWithProviders(<Harness />)
    await waitFor(() => expect(formApi).not.toBeNull())

    await selectTemplate({
      GUID: 'template-a',
      templateName: 'Sales',
      setManager: MANAGER,
    })

    await waitFor(() =>
      expect(formApi.getValues('setManager')).toEqual(MANAGER)
    )
  })

  it('clears the manager when switching to a template without one', async () => {
    renderWithProviders(<Harness />)
    await waitFor(() => expect(formApi).not.toBeNull())

    await selectTemplate({
      GUID: 'template-a',
      templateName: 'Sales',
      setManager: MANAGER,
    })
    await waitFor(() =>
      expect(formApi.getValues('setManager')).toEqual(MANAGER)
    )

    await selectTemplate({ GUID: 'template-b', templateName: 'Contractors' })

    await waitFor(() => expect(formApi.getValues('setManager')).toBeNull())
  })
})

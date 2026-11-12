import React from 'react'
import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useForm } from 'react-hook-form'
import { renderWithTheme } from '../../test-utils'
import { CippDirectTenantDeploy } from '../../../src/components/CippWizard/CippDirectTenantDeploy'

vi.mock('../../../src/api/ApiCall', async () => (await import('../../mocks/api-call')).apiCallMock())
import { api, postResult } from '../../mocks/api-call'

// capture what the deploy step hands the OAuth button
const buttonProps = []
vi.mock('../../../src/components/CippComponents/CIPPM365OAuthButton', () => ({
  CIPPM365OAuthButton: (props) => {
    buttonProps.push(props)
    return (
      <button type="button" onClick={() => props.onAuthSuccess({ accessToken: 'a', cloudEnvironment: props.cloudEnvironment })}>
        {props.buttonText}
      </button>
    )
  },
}))
vi.mock('../../../src/components/CippComponents/CippApiResults', () => ({ CippApiResults: () => null }))
vi.mock('../../../src/components/CippWizard/CippWizardStepButtons', () => ({ CippWizardStepButtons: () => null }))

const Harness = () => {
  const formControl = useForm()
  return <CippDirectTenantDeploy formControl={formControl} currentStep={0} />
}

// redanthrax/CIPP#2: the direct tenant step picks the cloud and passes its scope and cloud along.
describe('CippDirectTenantDeploy cloud choice', () => {
  let post
  beforeEach(() => {
    buttonProps.length = 0
    post = postResult()
    api.post = post
  })

  it('defaults to Commercial with the pre-#2 scope', () => {
    renderWithTheme(<Harness />)
    const props = buttonProps.at(-1)
    expect(props.cloudEnvironment).toBe('Commercial')
    expect(props.directTenant).toBe(true)
    expect(props.scope).toBe(
      'https://graph.microsoft.com/DelegatedPermissionGrant.ReadWrite.All https://graph.microsoft.com/Directory.ReadWrite.All https://graph.microsoft.com/AppRoleAssignment.ReadWrite.All offline_access profile openid'
    )
  })

  it.each([
    ['GCC High', 'USGovHigh', 'https://graph.microsoft.us/'],
    ['DoD', 'USGovDoD', 'https://dod-graph.microsoft.us/'],
  ])('switches to %s scopes and sends the cloud to ExecAddTenant', async (label, value, prefix) => {
    renderWithTheme(<Harness />)
    await userEvent.click(screen.getByRole('button', { name: label }))

    const props = buttonProps.at(-1)
    expect(props.cloudEnvironment).toBe(value)
    expect(props.scope).toContain(`${prefix}Directory.ReadWrite.All`)
    expect(props.scope).not.toContain('graph.microsoft.com')

    await userEvent.click(screen.getByRole('button', { name: 'Connect to Tenant' }))
    expect(post.mutate).toHaveBeenCalledWith({
      url: '/api/ExecAddTenant',
      data: expect.objectContaining({ cloudEnvironment: value, tenantMode: 'perTenant' }),
    })
  })
})

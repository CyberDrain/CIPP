import React from 'react'
import { screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithTheme } from '../../test-utils'
import { CippGovAppCredentials, GOV_APP_DOCS_URL, toPem } from '../../../src/components/CippSettings/CippGovAppCredentials'

vi.mock('../../../src/api/ApiCall', async () => (await import('../../mocks/api-call')).apiCallMock())
import { api, getResult, postResult } from '../../mocks/api-call'

vi.mock('../../../src/components/CippComponents/CippApiResults', () => ({ CippApiResults: () => null }))
vi.mock('../../../src/components/CippComponents/CippCopyToClipboard', () => ({
  CippCopyToClipBoard: ({ text }) => <span>{text}</span>,
}))

const GOV_APP_ID = '0a0a0a0a-1111-2222-3333-444444444444'

// redanthrax/CIPP#2: Azure Government app credentials on the Credentials page.
describe('CippGovAppCredentials', () => {
  let post

  beforeEach(() => {
    post = postResult()
    api.post = post
  })

  it('shows not configured', () => {
    api.get = getResult({ data: { Results: { configured: false, hasSecret: false, certificate: { configured: false }, authority: 'https://login.microsoftonline.us/organizations', redirectUri: 'https://cipp.example/authredirect' } } })
    renderWithTheme(<CippGovAppCredentials />)
    expect(screen.getByText('Not configured')).toBeInTheDocument()
    // The redirect URI is the one the sign-in button sends: this browser's origin, not the backend's guess
    expect(screen.getByText(`${window.location.origin}/authredirect`)).toBeInTheDocument()
    expect(screen.queryByText('https://cipp.example/authredirect')).not.toBeInTheDocument()
    expect(screen.getByText('https://login.microsoftonline.us/organizations')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Save' })).toBeDisabled()
  })

  it('points to the full permission requirement instead of listing a few permissions', () => {
    api.get = getResult({ data: { Results: { configured: false, hasSecret: false, certificate: { configured: false } } } })
    renderWithTheme(<CippGovAppCredentials />)
    expect(screen.getByText(/same Microsoft Graph permissions as CIPP-SAM/)).toBeInTheDocument()
    const link = screen.getByRole('link', { name: 'Permissions and setup guide' })
    expect(link).toHaveAttribute('href', GOV_APP_DOCS_URL)
    expect(GOV_APP_DOCS_URL).toContain('/setup/installation/government-direct-tenants')
  })

  it('saves the application id and secret through ExecGovAppCredentials', async () => {
    api.get = getResult({ data: { Results: { configured: false, hasSecret: false, certificate: { configured: false } } } })
    renderWithTheme(<CippGovAppCredentials />)

    await userEvent.type(screen.getByLabelText('Application (client) ID'), GOV_APP_ID)
    await userEvent.type(screen.getByLabelText('Client secret'), 's3cret')
    await userEvent.click(screen.getByRole('button', { name: 'Save' }))

    expect(post.mutate).toHaveBeenCalledWith({
      url: '/api/ExecGovAppCredentials',
      data: { Action: 'Save', applicationId: GOV_APP_ID, applicationSecret: 's3cret' },
    })
  })

  it('does not send a secret when the field is left empty', async () => {
    api.get = getResult({ data: { Results: { configured: true, applicationId: GOV_APP_ID, hasSecret: true, certificate: { configured: false } } } })
    renderWithTheme(<CippGovAppCredentials />)

    await userEvent.click(screen.getByRole('button', { name: 'Save' }))

    expect(post.mutate).toHaveBeenCalledWith({
      url: '/api/ExecGovAppCredentials',
      data: { Action: 'Save', applicationId: GOV_APP_ID },
    })
    expect(screen.getByText('Configured')).toBeInTheDocument()
    expect(screen.getByText('Stored')).toBeInTheDocument()
  })

  it('generates a certificate and offers the public part for download', async () => {
    api.get = getResult({ data: { Results: { configured: true, applicationId: GOV_APP_ID, hasSecret: false, certificate: { configured: true, thumbprint: 'ABC', notAfter: '2027-01-01', publicCertificate: 'TUlJQg==' } } } })
    renderWithTheme(<CippGovAppCredentials />)

    expect(screen.getByRole('button', { name: 'Download certificate' })).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: 'Generate new certificate' }))
    expect(post.mutate).toHaveBeenCalledWith({ url: '/api/ExecGovAppCredentials', data: { Action: 'GenerateCertificate' } })
  })

  it('says the certificate is used and disables the secret in certificate authentication mode', () => {
    api.get = getResult({ data: { Results: { configured: true, applicationId: GOV_APP_ID, hasSecret: false, certificateAuthMode: true, credentialInUse: 'certificate', certificate: { configured: true, thumbprint: 'ABC', notAfter: '2027-01-01', publicCertificate: 'TUlJQg==' } } } })
    renderWithTheme(<CippGovAppCredentials />)

    expect(screen.getByText('Certificate (this instance uses certificate authentication)')).toBeInTheDocument()
    expect(screen.getByLabelText('Client secret')).toBeDisabled()
    expect(screen.getByText(/Not used: this instance uses certificate authentication/)).toBeInTheDocument()
  })

  it('keeps the secret available and says it is used outside certificate mode', () => {
    api.get = getResult({ data: { Results: { configured: true, applicationId: GOV_APP_ID, hasSecret: true, certificateAuthMode: false, credentialInUse: 'secret', certificate: { configured: false } } } })
    renderWithTheme(<CippGovAppCredentials />)

    // the "Client secret" row label plus the "Signs in with" value
    expect(screen.getAllByText('Client secret', { selector: 'p' })).toHaveLength(2)
    expect(screen.queryByText(/^Certificate \(/)).not.toBeInTheDocument()
    expect(screen.getByLabelText(/New client secret/)).toBeEnabled()
    expect(screen.queryByText(/Not used: this instance uses certificate authentication/)).not.toBeInTheDocument()
  })

  it('warns when the app signs in with a certificate but none is stored', () => {
    api.get = getResult({ data: { Results: { configured: false, applicationId: GOV_APP_ID, hasSecret: false, certificateAuthMode: false, credentialInUse: 'certificate', certificate: { configured: false } } } })
    renderWithTheme(<CippGovAppCredentials />)

    expect(screen.getByText('Certificate (no client secret stored)')).toBeInTheDocument()
    expect(screen.getByText(/signs in with a certificate, but none is stored/)).toBeInTheDocument()
  })

  it('warns about an application id that has been typed but not saved', async () => {
    api.get = getResult({ data: { Results: { configured: false, hasSecret: false, certificate: { configured: true, thumbprint: 'ABC', notAfter: '2027-01-01', publicCertificate: 'TUlJQg==' } } } })
    renderWithTheme(<CippGovAppCredentials />)

    expect(screen.queryByText(/has not been saved yet/)).not.toBeInTheDocument()
    await userEvent.type(screen.getByLabelText('Application (client) ID'), GOV_APP_ID)
    expect(screen.getByText(/has not been saved yet/)).toBeInTheDocument()
  })

  it('does not warn once the typed id matches the saved one', () => {
    api.get = getResult({ data: { Results: { configured: true, applicationId: GOV_APP_ID, hasSecret: true, certificate: { configured: false } } } })
    renderWithTheme(<CippGovAppCredentials />)

    expect(screen.getByLabelText('Application (client) ID')).toHaveValue(GOV_APP_ID)
    expect(screen.queryByText(/has not been saved yet/)).not.toBeInTheDocument()
  })

  it('wraps the certificate as PEM', () => {
    expect(toPem('QUJD')).toBe('-----BEGIN CERTIFICATE-----\nQUJD\n-----END CERTIFICATE-----\n')
  })
})

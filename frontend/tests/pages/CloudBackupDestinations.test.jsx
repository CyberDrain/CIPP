import React from 'react'
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import router from 'next/router'
import TimeAgo from 'javascript-time-ago'
import en from 'javascript-time-ago/locale/en'
import { renderWithProviders } from '../test-utils'
import { api, getResult, postResult } from '../mocks/api-call'

vi.mock('../../src/api/ApiCall', async () =>
  (await import('../mocks/api-call')).apiCallMock()
)
const table = vi.hoisted(() => ({ props: null }))
vi.mock('../../src/components/CippComponents/CippTablePage.jsx', () => ({
  CippTablePage: (props) => {
    table.props = props
    return <div>{props.cardButton}</div>
  },
}))

import ListPage from '../../src/pages/cloud-backup/destinations/index.jsx'
import AddPage from '../../src/pages/cloud-backup/destinations/add.jsx'
import EditPage from '../../src/pages/cloud-backup/destinations/edit.jsx'

const s3Destination = getResult({
  data: [
    {
      Id: 'dest-2',
      Name: 'Wasabi',
      Provider: 'S3',
      Endpoint: 'https://s3.wasabisys.com',
      Region: 'eu-central-1',
      Bucket: 'msp-backups',
      AccessKeyId: 'AKIAEXAMPLE',
      ForcePathStyle: true,
      SecretSet: 'SentToKeyVault',
    },
  ],
})
const cippAppDestination = getResult({
  data: [
    {
      Id: 'dest-3',
      Name: 'Created by CIPP',
      Provider: 'AzureBlob',
      AuthMode: 'CippApp',
      ProvisionedBy: 'CIPP',
      StorageAccount: 'cippbackup7f3a',
      Container: 'cipp-backups',
      SubscriptionId: 'sub-1',
      ResourceGroup: 'rg-cipp-cloudbackup',
      ImmutabilityDays: 30,
    },
  ],
})
const emptyGet = getResult()

let post
beforeEach(() => {
  vi.clearAllMocks()
  post = postResult()
  api.post = () => post
  api.get = (opts) =>
    opts.url === '/api/ListCloudBackupDestinations' ? s3Destination : emptyGet
})

afterEach(() => {
  router.query = {}
})

try {
  TimeAgo.addDefaultLocale(en)
} catch {
  // already registered by an earlier file in this worker
}

const textbox = (name) => screen.getByRole('textbox', { name })
// the field's tooltip carries the same accessible name as its label
const secretInput = (name) => document.querySelector(`input[name="${name}"]`)

describe('Cloud Backup destination form', () => {
  it('lists the exact S3 permissions', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)

    await user.click(
      await screen.findByRole('combobox', { name: 'Storage provider' })
    )
    await user.click(
      await screen.findByRole('option', {
        name: 'Amazon S3 or S3-compatible storage',
      })
    )
    const permissions = [
      's3:PutObject',
      's3:GetObject',
      's3:GetObjectVersion',
      's3:DeleteObject',
      's3:AbortMultipartUpload',
      's3:ListBucket',
      's3:ListBucketVersions',
      's3:GetLifecycleConfiguration',
      's3:PutLifecycleConfiguration',
      's3:GetBucketVersioning',
    ]
    const shown = (await screen.findByText('s3:PutObject')).parentElement
    expect(
      [...shown.querySelectorAll('strong')].map((node) => node.textContent)
    ).toEqual(permissions)
  })

  it('explains that content backup needs versioning', async () => {
    renderWithProviders(<AddPage />)

    expect(
      await screen.findByRole('link', { name: 'Azure Blob Storage' })
    ).toHaveAttribute(
      'href',
      'https://learn.microsoft.com/azure/storage/blobs/versioning-enable'
    )
    expect(screen.getByRole('link', { name: 'Amazon S3' })).toHaveAttribute(
      'href',
      'https://docs.aws.amazon.com/AmazonS3/latest/userguide/manage-versioning-examples.html'
    )
  })

  it('shows the Azure fields and role guidance by default', async () => {
    renderWithProviders(<AddPage />)

    expect(
      await screen.findByRole('textbox', { name: 'Storage account name' })
    ).toBeInTheDocument()
    expect(textbox('Application (client) ID')).toBeInTheDocument()
    expect(secretInput('ClientSecret')).toBeInTheDocument()
    expect(screen.getByText('Storage Blob Data Owner')).toBeInTheDocument()
    expect(
      screen.queryByRole('textbox', { name: 'Bucket' })
    ).not.toBeInTheDocument()
  })

  it('swaps to the S3 fields when the provider changes', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)

    await user.click(
      await screen.findByRole('combobox', { name: 'Storage provider' })
    )
    await user.click(
      await screen.findByRole('option', {
        name: 'Amazon S3 or S3-compatible storage',
      })
    )

    expect(
      await screen.findByRole('textbox', { name: 'Bucket' })
    ).toBeInTheDocument()
    expect(textbox('Endpoint URL')).toBeInTheDocument()
    expect(secretInput('SecretAccessKey')).toBeInTheDocument()
    expect(screen.getByText('s3:PutLifecycleConfiguration')).toBeInTheDocument()
    expect(
      screen.queryByRole('textbox', { name: 'Storage account name' })
    ).not.toBeInTheDocument()
  })

  it('requires the Azure fields, including the secret, on add', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)

    await user.type(
      await screen.findByRole('textbox', { name: 'Destination name' }),
      'Azure prod'
    )
    await user.type(textbox('Storage account name'), 'cippbackups')
    await user.clear(textbox('Storage account name'))

    expect(
      await screen.findByText('Storage account name is required')
    ).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Submit' })).toBeDisabled()
  })

  it('posts only the Azure fields for an Azure destination', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)

    await user.type(
      await screen.findByRole('textbox', { name: 'Destination name' }),
      'Azure prod'
    )
    await user.type(textbox('Storage account name'), 'cippbackups')
    await user.type(textbox('Container'), 'config')
    await user.type(textbox('Subscription ID'), 'sub-1')
    await user.type(textbox('Resource group'), 'rg-backup')
    await user.type(textbox('Directory (tenant) ID'), 'tid-1')
    await user.type(textbox('Application (client) ID'), 'app-1')
    await user.type(secretInput('ClientSecret'), 's3cret')

    const submit = screen.getByRole('button', { name: 'Submit' })
    await waitFor(() => expect(submit).toBeEnabled())
    await user.click(submit)

    await waitFor(() => expect(post.mutate).toHaveBeenCalledTimes(1))
    const { url, data } = post.mutate.mock.calls[0][0]
    expect(url).toBe('/api/ExecCloudBackupDestination')
    expect(data).toEqual({
      Action: 'Add',
      Name: 'Azure prod',
      Provider: 'AzureBlob',
      StorageAccount: 'cippbackups',
      Container: 'config',
      SubscriptionId: 'sub-1',
      ResourceGroup: 'rg-backup',
      AzureTenantId: 'tid-1',
      ClientId: 'app-1',
      ClientSecret: 's3cret',
    })
  })

  it('keeps the stored secret on edit by sending the Key Vault placeholder', async () => {
    const user = userEvent.setup()
    router.query = { id: 'dest-2' }
    renderWithProviders(<EditPage />)

    expect(await screen.findByDisplayValue('msp-backups')).toBeInTheDocument()
    expect(secretInput('SecretAccessKey')).toHaveValue('SentToKeyVault')
    expect(
      screen.getByText(/Leave as is to keep the stored secret/)
    ).toBeInTheDocument()

    await user.clear(textbox('Destination name'))
    await user.type(textbox('Destination name'), 'Wasabi EU')
    const submit = screen.getByRole('button', { name: 'Submit' })
    await waitFor(() => expect(submit).toBeEnabled())
    await user.click(submit)

    await waitFor(() => expect(post.mutate).toHaveBeenCalledTimes(1))
    expect(post.mutate.mock.calls[0][0].data).toEqual({
      Action: 'Edit',
      Id: 'dest-2',
      Name: 'Wasabi EU',
      Provider: 'S3',
      Endpoint: 'https://s3.wasabisys.com',
      Region: 'eu-central-1',
      Bucket: 'msp-backups',
      AccessKeyId: 'AKIAEXAMPLE',
      SecretAccessKey: 'SentToKeyVault',
      ForcePathStyle: true,
    })
  })

  it('does not require a new secret on edit', async () => {
    const user = userEvent.setup()
    router.query = { id: 'dest-2' }
    renderWithProviders(<EditPage />)

    await screen.findByDisplayValue('msp-backups')
    const secret = secretInput('SecretAccessKey')
    expect(secret).toHaveValue('SentToKeyVault')
    await user.clear(secret)
    await user.type(textbox('Bucket'), '-2')

    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Submit' })).toBeEnabled()
    )
    expect(
      screen.queryByText('Secret access key is required')
    ).not.toBeInTheDocument()
  })
})

describe('Cloud Backup destination created by CIPP', () => {
  it('edits without an app registration or secret', async () => {
    const user = userEvent.setup()
    api.get = (opts) =>
      opts.url === '/api/ListCloudBackupDestinations'
        ? cippAppDestination
        : emptyGet
    router.query = { id: 'dest-3' }
    renderWithProviders(<EditPage />)

    expect(
      await screen.findByDisplayValue('cippbackup7f3a')
    ).toBeInTheDocument()
    expect(
      screen.getByText(/signs in to it with its own app/)
    ).toBeInTheDocument()
    expect(secretInput('ClientSecret')).toBeNull()
    expect(
      screen.queryByRole('textbox', { name: 'Application (client) ID' })
    ).not.toBeInTheDocument()
    expect(
      screen.queryByRole('textbox', { name: 'Directory (tenant) ID' })
    ).not.toBeInTheDocument()

    await user.clear(textbox('Destination name'))
    await user.type(textbox('Destination name'), 'Azure backups')
    const submit = screen.getByRole('button', { name: 'Submit' })
    await waitFor(() => expect(submit).toBeEnabled())
    await user.click(submit)

    await waitFor(() => expect(post.mutate).toHaveBeenCalledTimes(1))
    expect(post.mutate.mock.calls[0][0].data).toEqual({
      Action: 'Edit',
      Id: 'dest-3',
      Name: 'Azure backups',
      Provider: 'AzureBlob',
      StorageAccount: 'cippbackup7f3a',
      Container: 'cipp-backups',
      SubscriptionId: 'sub-1',
      ResourceGroup: 'rg-cipp-cloudbackup',
    })
  })
})

describe('Cloud Backup destinations list', () => {
  const action = (label) =>
    table.props.actions.find((item) => item.label === label)

  it('tests a stored destination', () => {
    renderWithProviders(<ListPage />)

    expect(table.props.apiUrl).toBe('/api/ListCloudBackupDestinations')
    expect(table.props.queryKey).toBe('ListCloudBackupDestinations')
    expect(action('Test Connection')).toMatchObject({
      type: 'POST',
      url: '/api/ExecCloudBackupDestination',
      data: { Action: '!Test', Id: 'Id' },
    })
    expect(action('Test Connection').relatedQueryKeys).toContain(
      'ListCloudBackupDestinations*'
    )
    expect(action('Delete Destination').data).toEqual({
      Action: '!Delete',
      Id: 'Id',
    })
  })

  it('shows each check of the last test in the details drawer', () => {
    renderWithProviders(<ListPage />)
    renderWithProviders(
      table.props.offCanvas.children({
        Id: 'dest-1',
        Name: 'Azure prod',
        Provider: 'AzureBlob',
        Location: 'cippbackups/config',
        PolicyCount: 1,
        SecretSet: 'SentToKeyVault',
        LastTestedAt: '2026-11-19T10:00:00Z',
        LastTestStatus: 'Failed',
        LastTest: {
          Write: true,
          Read: true,
          Delete: true,
          Lifecycle: false,
          Versioning: 'Disabled',
          Errors: [
            'AuthorizationPermissionMismatch reading the management policy',
          ],
        },
      })
    )

    expect(screen.getByText('Azure Blob Storage')).toBeInTheDocument()
    expect(screen.getByText('Stored in Key Vault')).toBeInTheDocument()
    expect(screen.getAllByText('Passed')).toHaveLength(3)
    expect(
      screen.queryByText('Can remove expired versions')
    ).not.toBeInTheDocument()
    expect(screen.getAllByText('Failed')).toHaveLength(2)
    expect(screen.getByText('Off')).toBeInTheDocument()
    expect(
      screen.getByText(/Content backup needs versioning/)
    ).toBeInTheDocument()
    expect(
      screen.getByText(
        'AuthorizationPermissionMismatch reading the management policy'
      )
    ).toBeInTheDocument()
  })

  it('shows a destination ready for content backup', () => {
    renderWithProviders(<ListPage />)
    renderWithProviders(
      table.props.offCanvas.children({
        Id: 'dest-2',
        Name: 'S3 archive',
        Provider: 'S3',
        LastTestedAt: '2026-11-19T10:00:00Z',
        LastTest: {
          Write: true,
          Read: true,
          Delete: true,
          Lifecycle: true,
          Versioning: 'Enabled',
          VersionDelete: true,
          ContentReady: true,
          Errors: [],
        },
      })
    )

    expect(screen.getByText('Destination: S3 archive')).toBeInTheDocument()
    expect(screen.getByText('On')).toBeInTheDocument()
    expect(screen.getByText('Can remove expired versions')).toBeInTheDocument()
    expect(screen.getAllByText('Passed')).toHaveLength(6)
    expect(
      screen.queryByText(/Content backup needs versioning/)
    ).not.toBeInTheDocument()
  })

  it.each([
    [{ Versioning: 'Enabled', ContentReady: true }, 'On'],
    [{ Versioning: 'Enabled', ContentReady: false }, 'Off'],
    [{ Versioning: 'Enabled' }, 'On'],
    [{ Versioning: 'Suspended' }, 'Off'],
    [{ Versioning: 'Unknown' }, 'Unknown'],
    [null, 'Not tested'],
  ])('shows versioning %j as %s in the table', (lastTest, label) => {
    renderWithProviders(<ListPage />)
    expect(
      table.props.dataMap({ LastTest: lastTest }).CloudBackupVersioning
    ).toBe(label)
    expect(table.props.simpleColumns).toContain('CloudBackupVersioning')
  })

  it('shows how a destination was set up and signs in', () => {
    renderWithProviders(<ListPage />)
    renderWithProviders(
      table.props.offCanvas.children(cippAppDestination.data[0])
    )

    expect(screen.getByText('Created by CIPP')).toBeInTheDocument()
    expect(screen.getByText('CIPP’s own app')).toBeInTheDocument()
    expect(screen.getByText('30 days')).toBeInTheDocument()
    expect(screen.getByText('Not needed')).toBeInTheDocument()
    expect(table.props.simpleColumns).toContain('CloudBackupSignIn')
    expect(
      table.props.dataMap({ Provider: 'AzureBlob' }).CloudBackupSignIn
    ).toBe('App registration')
    expect(table.props.dataMap({ Provider: 'S3' }).CloudBackupSignIn).toBe(
      'Access key'
    )
  })

  it('leaves out set-up and immutability details for a manual destination', () => {
    renderWithProviders(<ListPage />)
    renderWithProviders(
      table.props.offCanvas.children({
        Id: 'dest-1',
        Name: 'Azure prod',
        Provider: 'AzureBlob',
        AuthMode: 'ServicePrincipal',
        ProvisionedBy: '',
        SecretSet: 'SentToKeyVault',
      })
    )

    expect(screen.getByText('App registration')).toBeInTheDocument()
    expect(screen.queryByText('Created by CIPP')).not.toBeInTheDocument()
    expect(screen.queryByText('Immutable for')).not.toBeInTheDocument()
  })

  it('names the provider in the table rows', () => {
    renderWithProviders(<ListPage />)
    expect(
      table.props.dataMap({ Provider: 'S3', LastTestStatus: 'Failed' })
    ).toMatchObject({
      Provider: 'S3',
      LastTestStatus: 'Failed',
      CloudBackupProviderName: 'Amazon S3 or S3-compatible storage',
      CloudBackupLastTest: 'Failed',
    })
  })
})

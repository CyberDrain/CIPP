import React, { useSyncExternalStore } from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { act, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithProviders } from '../test-utils'
import { api, getResult, postResult } from '../mocks/api-call'

vi.mock('../../src/api/ApiCall', async () =>
  (await import('../mocks/api-call')).apiCallMock()
)

import { ApiGetCall } from '../../src/api/ApiCall'
import AddPage from '../../src/pages/cloud-backup/destinations/add.jsx'
import {
  cloudBackupProvisionRunning,
  cloudBackupRegionOptions,
  formatCloudBackupProvision,
} from '../../src/utils/cloud-backup'

const availableOptions = getResult({
  data: {
    Available: true,
    ManagedIdentity: 'cipp-prod-identity',
    Subscriptions: [
      { id: 'sub-1', name: 'Contoso Prod' },
      { id: 'sub-2', name: 'Contoso Dev' },
    ],
  },
})
const unavailableOptions = getResult({
  data: {
    Available: false,
    Reason: 'CIPP is not running with a managed identity.',
    Subscriptions: [],
  },
})
const regions = getResult({
  data: {
    Regions: [
      { name: 'eastus', displayName: 'East US' },
      { name: 'westeurope', displayName: 'West Europe' },
    ],
  },
})

const steps = (statuses, message) =>
  [
    'Create resource group',
    'Create storage account',
    'Create container',
    'Grant CIPP access',
  ].map((Name, index) => ({
    Name,
    Status: statuses[index],
    Message: statuses[index] === 'Failed' ? message : '',
  }))

const jobs = {
  running: getResult({
    data: {
      Id: 'job-1',
      Type: 'Provision',
      Status: 'Running',
      Steps: steps(['Completed', 'Running', 'Pending', 'Pending']),
    },
  }),
  completed: getResult({
    data: {
      Id: 'job-1',
      Type: 'Provision',
      Status: 'Completed',
      Steps: steps(['Completed', 'Completed', 'Completed', 'Completed']),
      Result: {
        DestinationId: 'dest-9',
        SubscriptionId: 'sub-1',
        ResourceGroup: 'rg-cipp-cloudbackup',
        StorageAccount: 'cippbackup7f3a',
        Container: 'cipp-backups',
        Region: 'eastus',
      },
    },
  }),
  failed: getResult({
    data: [
      {
        Id: 'job-1',
        Type: 'Provision',
        Status: 'Failed',
        Steps: steps(
          ['Completed', 'Completed', 'Completed', 'Failed'],
          'The managed identity is not allowed to assign roles.'
        ),
        Result: {
          SubscriptionId: 'sub-1',
          ResourceGroup: 'rg-cipp-cloudbackup',
          StorageAccount: 'cippbackup7f3a',
          Container: 'cipp-backups',
          Region: 'eastus',
        },
        Error: 'The managed identity is not allowed to assign roles.',
      },
    ],
  }),
}

const jobStore = { value: jobs.running, listeners: new Set() }
const subscribe = (listener) => {
  jobStore.listeners.add(listener)
  return () => jobStore.listeners.delete(listener)
}
const useJob = () => useSyncExternalStore(subscribe, () => jobStore.value)
const setJob = (value) =>
  act(() => {
    jobStore.value = value
    jobStore.listeners.forEach((listener) => listener())
  })

let options
let post
const emptyGet = getResult()

const useRoutedGet = (opts) => {
  const job = useJob()
  if (opts.url === '/api/ListCloudBackupProvisioningOptions') {
    return opts.data?.SubscriptionId ? regions : options
  }
  if (opts.url === '/api/ListCloudBackupJobs') {
    return job
  }
  return emptyGet
}

beforeEach(() => {
  vi.clearAllMocks()
  options = availableOptions
  jobStore.value = jobs.running
  post = postResult()
  api.post = (opts) => {
    post.mutate.mockImplementation(() =>
      opts.onResult?.({
        Results: 'Creating the storage account.',
        JobId: 'job-1',
      })
    )
    return post
  }
  api.get = useRoutedGet
})

const jobCall = () =>
  ApiGetCall.mock.calls
    .map(([opts]) => opts)
    .filter((opts) => opts.url === '/api/ListCloudBackupJobs')
    .at(-1)

const textbox = (name) => screen.getByRole('textbox', { name })

const choose = async (user, combobox, option) => {
  await user.click(screen.getByRole('combobox', { name: combobox }))
  await user.click(await screen.findByRole('option', { name: option }))
}

const fillCreateForm = async (user) => {
  await user.type(
    await screen.findByRole('textbox', { name: 'Destination name' }),
    'Azure backups'
  )
  await choose(user, 'Subscription', 'Contoso Prod')
  await choose(user, 'Region', 'East US')
}

const submit = async (user) => {
  const button = screen.getByRole('button', { name: 'Submit' })
  await waitFor(() => expect(button).toBeEnabled())
  await user.click(button)
}

describe('Cloud Backup automatic storage setup', () => {
  it('preselects creating a storage account when CIPP can', async () => {
    renderWithProviders(<AddPage />)

    expect(
      await screen.findByRole('radio', {
        name: 'Create a storage account for me (recommended)',
      })
    ).toBeChecked()
    expect(textbox('New resource group name')).toHaveValue(
      'rg-cipp-cloudbackup'
    )
    expect(textbox('Container name')).toHaveValue('cipp-backups')
    expect(
      screen.getByRole('radio', { name: /Locally redundant \(LRS\)/ })
    ).toBeChecked()
    expect(screen.getByText(/cipp-prod-identity/)).toBeInTheDocument()
    expect(
      screen.getByText(
        'Account keys turned off: CIPP signs in with its own app'
      )
    ).toBeInTheDocument()
    expect(
      screen.queryByRole('textbox', { name: 'Storage account name' })
    ).not.toBeInTheDocument()
  })

  it('falls back to manual setup and says why when CIPP can’t create storage', async () => {
    options = unavailableOptions
    renderWithProviders(<AddPage />)

    expect(
      await screen.findByRole('radio', {
        name: 'Create a storage account for me (recommended)',
      })
    ).toBeDisabled()
    expect(
      screen.getByRole('radio', {
        name: 'Use an existing Azure storage account or S3 bucket',
      })
    ).toBeChecked()
    expect(
      screen.getByText(/CIPP is not running with a managed identity/)
    ).toBeInTheDocument()
    expect(screen.getByText('User Access Administrator')).toBeInTheDocument()
    expect(textbox('Storage account name')).toBeInTheDocument()
  })

  it('switches to the manual form when chosen', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)

    await user.click(
      await screen.findByRole('radio', {
        name: 'Use an existing Azure storage account or S3 bucket',
      })
    )
    expect(textbox('Storage account name')).toBeInTheDocument()
    expect(
      screen.queryByRole('textbox', { name: 'New resource group name' })
    ).not.toBeInTheDocument()
  })

  it('rejects an invalid container name and immutability period', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)
    await fillCreateForm(user)

    await user.clear(textbox('Container name'))
    await user.type(textbox('Container name'), 'Bad_Name')
    expect(
      await screen.findByText(/Use 3 to 63 lowercase letters/)
    ).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Submit' })).toBeDisabled()

    await user.clear(textbox('Container name'))
    await user.type(textbox('Container name'), 'backups')
    await user.click(
      screen.getByRole('switch', { name: 'Make backups immutable' })
    )
    expect(
      screen.getByText(/Backups can't be deleted before this period ends/)
    ).toBeInTheDocument()
    const days = screen.getByRole('spinbutton', {
      name: 'Immutable for (days)',
    })
    await user.clear(days)
    await user.type(days, '5000')
    expect(await screen.findByText('Use at most 3650 days')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Submit' })).toBeDisabled()
  })

  it('posts the provisioning request with the defaults', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)
    await fillCreateForm(user)
    await submit(user)

    await waitFor(() => expect(post.mutate).toHaveBeenCalledTimes(1))
    const { url, data } = post.mutate.mock.calls[0][0]
    expect(url).toBe('/api/ExecCloudBackupProvision')
    expect(data).toEqual({
      Name: 'Azure backups',
      SubscriptionId: 'sub-1',
      ResourceGroup: 'rg-cipp-cloudbackup',
      Region: 'eastus',
      Redundancy: 'Standard_LRS',
      Container: 'cipp-backups',
    })
  })

  it('sends the immutability period only when it is turned on', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)
    await fillCreateForm(user)
    await user.click(
      screen.getByRole('radio', { name: /Zone redundant \(ZRS\)/ })
    )
    await user.click(
      screen.getByRole('switch', { name: 'Make backups immutable' })
    )
    await submit(user)

    await waitFor(() => expect(post.mutate).toHaveBeenCalledTimes(1))
    expect(post.mutate.mock.calls[0][0].data).toMatchObject({
      Redundancy: 'Standard_ZRS',
      ImmutabilityDays: 30,
    })
  })

  it('polls the job and shows the new storage once it completes', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)
    await fillCreateForm(user)
    await submit(user)

    expect(
      await screen.findByText('Creating your storage account')
    ).toBeInTheDocument()
    expect(jobCall()).toMatchObject({
      url: '/api/ListCloudBackupJobs',
      data: { Id: 'job-1' },
      queryKey: 'ListCloudBackupJobs-provision-job-1',
    })
    expect(jobCall().data).not.toHaveProperty('tenantFilter')
    expect(
      jobCall().refetchInterval({ state: { data: jobs.running.data } })
    ).toBe(3000)
    expect(screen.getByText('Create storage account')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: 'Submit' })).toBeNull()

    setJob(jobs.completed)

    expect(
      await screen.findByText('Your storage account is ready')
    ).toBeInTheDocument()
    expect(
      jobCall().refetchInterval({ state: { data: jobs.completed.data } })
    ).toBe(false)
    expect(screen.getByText('cippbackup7f3a')).toBeInTheDocument()
    expect(
      screen.getByRole('link', { name: 'View destination' })
    ).toHaveAttribute('href', '/cloud-backup/destinations')
    expect(
      screen.getByRole('link', { name: 'Add a backup policy' })
    ).toHaveAttribute('href', '/cloud-backup/policies/add')
  })

  it('warns when the storage is ready but the connection test has not passed yet', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)
    await fillCreateForm(user)
    await submit(user)

    setJob(
      getResult({
        data: {
          ...jobs.completed.data,
          Steps: steps(
            ['Completed', 'Completed', 'Completed', 'Failed'],
            'Access can take up to 10 minutes'
          ),
          Result: { ...jobs.completed.data.Result, TestPassed: false },
        },
      })
    )

    expect(
      await screen.findByText('Your storage account is ready')
    ).toBeInTheDocument()
    expect(
      screen.getByText(/Test the destination again from Destinations/)
    ).toBeInTheDocument()
    expect(
      screen.queryByRole('button', { name: /Set up manually instead/ })
    ).toBeNull()
  })

  it('shows the failed step and prefills the manual form from the job', async () => {
    const user = userEvent.setup()
    renderWithProviders(<AddPage />)
    await fillCreateForm(user)
    await submit(user)
    await screen.findByText('Creating your storage account')

    setJob(jobs.failed)

    const alert = await screen.findByRole('alert')
    expect(within(alert).getByText('Grant CIPP access')).toBeInTheDocument()
    expect(alert).toHaveTextContent(
      'The managed identity is not allowed to assign roles.'
    )
    expect(
      jobCall().refetchInterval({ state: { data: jobs.failed.data } })
    ).toBe(false)

    await user.click(
      screen.getByRole('button', { name: 'Set up manually instead' })
    )

    expect(
      await screen.findByRole('textbox', { name: 'Storage account name' })
    ).toHaveValue('cippbackup7f3a')
    expect(textbox('Destination name')).toHaveValue('Azure backups')
    expect(textbox('Container')).toHaveValue('cipp-backups')
    expect(textbox('Subscription ID')).toHaveValue('sub-1')
    expect(textbox('Resource group')).toHaveValue('rg-cipp-cloudbackup')
    expect(textbox('Application (client) ID')).toHaveValue('')
    expect(
      screen.getByRole('radio', {
        name: 'Use an existing Azure storage account or S3 bucket',
      })
    ).toBeChecked()
  })
})

describe('Cloud Backup provisioning helpers', () => {
  it('reads regions as an array or wrapped in Regions', () => {
    const list = [{ name: 'uksouth', displayName: 'UK South' }]
    const expected = [{ label: 'UK South', value: 'uksouth' }]
    expect(cloudBackupRegionOptions(list)).toEqual(expected)
    expect(cloudBackupRegionOptions({ Regions: list })).toEqual(expected)
    expect(cloudBackupRegionOptions(undefined)).toEqual([])
  })

  it('keeps polling only while the job is queued or running', () => {
    expect(cloudBackupProvisionRunning(undefined)).toBe(true)
    expect(cloudBackupProvisionRunning({ Status: 'Queued' })).toBe(true)
    expect(cloudBackupProvisionRunning({ Status: 'Running' })).toBe(true)
    expect(cloudBackupProvisionRunning({ Status: 'Completed' })).toBe(false)
    expect(cloudBackupProvisionRunning({ Status: 'Failed' })).toBe(false)
  })

  it('reads select values given as options', () => {
    expect(
      formatCloudBackupProvision({
        Name: ' Prod ',
        SubscriptionId: { label: 'Contoso', value: 'sub-1' },
        ResourceGroup: 'rg-x',
        Region: { label: 'East US', value: 'eastus' },
        Container: 'c1',
        Immutability: false,
        ImmutabilityDays: 30,
      })
    ).toEqual({
      Name: 'Prod',
      SubscriptionId: 'sub-1',
      ResourceGroup: 'rg-x',
      Region: 'eastus',
      Redundancy: 'Standard_LRS',
      Container: 'c1',
    })
  })
})

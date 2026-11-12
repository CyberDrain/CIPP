import React from 'react'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithProviders, settingsWith } from '../test-utils'
import { api, getResult, paginatedResult, postResult } from '../mocks/api-call'
import { CippApiDialog } from '../../src/components/CippComponents/CippApiDialog'

const tableProps = vi.hoisted(() => ({ current: null }))
vi.mock('../../src/api/ApiCall', async () =>
  (await import('../mocks/api-call')).apiCallMock()
)
vi.mock('../../src/components/CippComponents/CippTablePage.jsx', () => ({
  CippTablePage: (props) => {
    tableProps.current = props
    return <div data-testid="table-page-stub" />
  },
}))

import Page from '../../src/pages/identity/administration/users/user-defaults.jsx'

const template = {
  GUID: 'template-a',
  tenantFilter: 'testdomain.com',
  templateName: 'Sales',
}
const usersResult = paginatedResult([
  {
    id: 'user-1',
    displayName: 'Jane Doe',
    userPrincipalName: 'jane@contoso.com',
  },
])
const emptyPaginated = paginatedResult([])
const emptyGet = getResult()
const settings = settingsWith({
  userAttributes: [{ label: 'sponsor', value: 'sponsor' }],
})

describe('User Templates page - sponsor', () => {
  let post

  beforeEach(() => {
    post = postResult()
    api.get = emptyGet
    api.post = () => post
    api.paginated = (opts) =>
      opts?.data?.Endpoint === 'users' ? usersResult : emptyPaginated
  })

  it('saves the picked sponsor on the template by user principal name', async () => {
    const user = userEvent.setup()
    const { unmount } = renderWithProviders(<Page />, { settings })
    const action = tableProps.current.actions.find(
      (entry) => entry.label === 'Edit Template'
    )
    unmount()

    renderWithProviders(
      <CippApiDialog
        createDialog={{ open: true, handleClose: vi.fn() }}
        title="Edit Template"
        fields={action.fields}
        api={action}
        row={template}
      />
    )

    await user.click(screen.getByRole('combobox', { name: 'Set Sponsor' }))
    await user.click(
      await screen.findByRole('option', { name: 'Jane Doe (jane@contoso.com)' })
    )
    await user.click(screen.getByRole('button', { name: 'Confirm' }))

    await waitFor(() => expect(post.mutate).toHaveBeenCalledTimes(1))
    expect(post.mutate.mock.calls[0][0].data.setSponsor).toMatchObject({
      label: 'Jane Doe (jane@contoso.com)',
      value: 'jane@contoso.com',
    })
  })
})

import React from 'react'
import { screen, fireEvent, act } from '@testing-library/react'
import { renderWithTheme } from '../../test-utils'
import { CIPPM365OAuthButton } from '../../../src/components/CippComponents/CIPPM365OAuthButton'

vi.mock('../../../src/api/ApiCall', async () => (await import('../../mocks/api-call')).apiCallMock())
import { api, getResult } from '../../mocks/api-call'

// only rendered for promptBeforeAuth / device-code paths, cut their import trees
vi.mock('../../../src/components/CippComponents/CippApiDialog', () => ({
  CippApiDialog: () => null,
}))
vi.mock('../../../src/components/CippComponents/CippCopyToClipboard', () => ({
  CippCopyToClipBoard: ({ text }) => <span>{text}</span>,
}))

const APP_ID = 'f8b2c3d4-9e01-4a23-8b45-6c7d8e9f0a1b'

// The popup flow listens on BroadcastChannel('cipp_auth') for the /authredirect
// callback. A controllable stub lets tests deliver results synchronously.
class MockBroadcastChannel {
  static instances = []
  constructor(name) {
    this.name = name
    this.onmessage = null
    this.postMessage = vi.fn()
    this.close = vi.fn()
    MockBroadcastChannel.instances.push(this)
  }
}

const lastChannel = () => MockBroadcastChannel.instances.at(-1)

const authButton = () => screen.getByRole('button', { name: /Login with Microsoft|Authenticating/ })

describe('CIPPM365OAuthButton popup flow', () => {
  let openSpy

  beforeEach(() => {
    vi.useFakeTimers()
    vi.stubGlobal('BroadcastChannel', MockBroadcastChannel)
    MockBroadcastChannel.instances.length = 0
    api.get = getResult({ data: { applicationId: APP_ID } })
    openSpy = vi.spyOn(window, 'open')
    // The PKCE S256 challenge awaits a real digest, which settles on the event loop
    // rather than the microtask queue and so cannot be flushed under fake timers.
    // A resolved stub keeps the popup setup that follows it deterministic.
    vi.spyOn(globalThis.crypto.subtle, 'digest').mockResolvedValue(new Uint8Array(32).buffer)
  })

  // Everything after the digest - the BroadcastChannel and the popup watcher - is set up
  // in a microtask, so tests touching those have to let the click settle first.
  const settleAuthStart = () => act(async () => {})

  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it('fails fast with a clear error when the browser blocks the popup', () => {
    openSpy.mockReturnValue(null)
    const onAuthError = vi.fn()
    renderWithTheme(<CIPPM365OAuthButton applicationId={APP_ID} onAuthError={onAuthError} />)

    fireEvent.click(authButton())

    expect(screen.getByText(/blocked by the browser/)).toBeInTheDocument()
    expect(onAuthError).toHaveBeenCalledWith(expect.objectContaining({ errorCode: 'popup_blocked' }))
    // not stuck on "Authenticating..." - immediately retryable
    expect(screen.getByRole('button', { name: 'Login with Microsoft' })).toBeEnabled()
  })

  it('re-enables the button shortly after the sign-in window is closed without a result', async () => {
    const popup = { closed: false, close: vi.fn() }
    openSpy.mockReturnValue(popup)
    const onAuthError = vi.fn()
    renderWithTheme(<CIPPM365OAuthButton applicationId={APP_ID} onAuthError={onAuthError} />)

    fireEvent.click(authButton())
    expect(screen.getByRole('button', { name: /Authenticating/ })).toBeDisabled()
    await settleAuthStart()

    popup.closed = true
    // 1s watcher tick spots the closed window, then the 2s grace period elapses
    act(() => {
      vi.advanceTimersByTime(1000)
    })
    act(() => {
      vi.advanceTimersByTime(2000)
    })

    expect(screen.getByText(/sign-in window was closed/)).toBeInTheDocument()
    expect(onAuthError).toHaveBeenCalledWith(expect.objectContaining({ errorCode: 'popup_closed' }))
    expect(screen.getByRole('button', { name: 'Login with Microsoft' })).toBeEnabled()
  })

  it('does not report a cancellation when a result arrived before the popup closed', async () => {
    const popup = { closed: false, close: vi.fn() }
    openSpy.mockReturnValue(popup)
    renderWithTheme(<CIPPM365OAuthButton applicationId={APP_ID} />)

    fireEvent.click(authButton())
    await settleAuthStart()

    // the /authredirect callback posts its result, then the popup closes itself
    act(() => {
      lastChannel().onmessage({
        data: {
          type: 'auth_error',
          error: 'access_denied',
          errorDescription: 'The user cancelled at the Microsoft sign-in page.',
        },
      })
    })
    popup.closed = true
    act(() => {
      vi.advanceTimersByTime(10000)
    })

    // the real result is shown, never overridden by the popup-closed cancellation
    expect(screen.getByText(/Authentication Error: access_denied/)).toBeInTheDocument()
    expect(screen.queryByText(/sign-in window was closed/)).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Login with Microsoft' })).toBeEnabled()
  })

  it('cleans up the popup watcher when a result arrives', async () => {
    const popup = { closed: false, close: vi.fn() }
    openSpy.mockReturnValue(popup)
    renderWithTheme(<CIPPM365OAuthButton applicationId={APP_ID} />)

    fireEvent.click(authButton())
    await settleAuthStart()
    act(() => {
      lastChannel().onmessage({
        data: { type: 'auth_error', error: 'access_denied', errorDescription: 'cancelled' },
      })
    })

    expect(lastChannel().close).toHaveBeenCalled()
    // with the watcher cleared, no timers remain to fire popup_closed later
    expect(vi.getTimerCount()).toBe(0)
  })

  it('cancels the pending close check when a result lands during the grace period', async () => {
    const popup = { closed: false, close: vi.fn() }
    openSpy.mockReturnValue(popup)
    renderWithTheme(<CIPPM365OAuthButton applicationId={APP_ID} />)

    fireEvent.click(authButton())
    await settleAuthStart()

    // the callback closes the popup first, so the watcher schedules its grace check...
    popup.closed = true
    act(() => {
      vi.advanceTimersByTime(1000)
    })
    // ...and the result lands inside that window
    act(() => {
      lastChannel().onmessage({
        data: { type: 'auth_error', error: 'access_denied', errorDescription: 'cancelled' },
      })
    })

    // nothing left pending that could fire against a subsequent attempt
    expect(vi.getTimerCount()).toBe(0)

    act(() => {
      vi.advanceTimersByTime(5000)
    })
    expect(screen.getByText(/Authentication Error: access_denied/)).toBeInTheDocument()
    expect(screen.queryByText(/sign-in window was closed/)).not.toBeInTheDocument()
  })
})

describe('CIPPM365OAuthButton device code flow', () => {
  let openSpy

  beforeEach(() => {
    vi.useFakeTimers()
    api.get = getResult({ data: { applicationId: APP_ID } })
    openSpy = vi.spyOn(window, 'open')
    // keep the poll pending so the flow stays mid-authentication
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue({
        ok: true,
        json: async () => ({ status: 'pending', error: 'authorization_pending' }),
      })
    )
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  const codeResponse = (userCode, deviceCode) => ({
    ok: true,
    json: async () => ({
      user_code: userCode,
      device_code: deviceCode,
      expires_in: 900,
      interval: 5,
    }),
  })

  const pendingResponse = {
    ok: true,
    json: async () => ({ status: 'pending', error: 'authorization_pending' }),
  }

  it('offers a fresh code instead of locking up when the sign-in window is closed', async () => {
    const popup = { closed: false, close: vi.fn() }
    openSpy.mockReturnValue(popup)
    global.fetch = vi.fn().mockResolvedValue(codeResponse('FHA953X4X', 'dev-code-1'))

    renderWithTheme(<CIPPM365OAuthButton applicationId={APP_ID} useDeviceCode />)

    // first click retrieves the device code
    fireEvent.click(screen.getByRole('button', { name: /Login with Microsoft/ }))
    await act(async () => {})

    // second click opens the popup and starts polling
    global.fetch = vi.fn().mockResolvedValue(pendingResponse)
    fireEvent.click(screen.getByRole('button', { name: /Authenticate with Code/ }))
    await act(async () => {})
    expect(screen.getByRole('button', { name: /Authenticating/ })).toBeDisabled()

    // the user closes the sign-in window
    popup.closed = true
    await act(async () => {
      vi.advanceTimersByTime(1000)
    })

    const restart = screen.getByRole('button', { name: /Start over with a new code/ })
    expect(restart).toBeEnabled()
    // the copy must not promise that the old code can be reused - it is consumed once entered
    expect(screen.getByText(/cannot be used again/)).toBeInTheDocument()

    // starting over requests a new code and retires the old poll
    global.fetch = vi.fn().mockResolvedValue(codeResponse('NEWCODE99', 'dev-code-2'))
    fireEvent.click(restart)
    await act(async () => {})

    expect(screen.getByText('NEWCODE99')).toBeInTheDocument()

    // the superseded poll must not keep hitting the old device code
    global.fetch.mockClear()
    await act(async () => {
      vi.advanceTimersByTime(30000)
    })
    const polledOldCode = global.fetch.mock.calls.some(([url]) =>
      String(url).includes('dev-code-1')
    )
    expect(polledOldCode).toBe(false)
  })
})

// redanthrax/CIPP#2: a government cloud signs in at its own authority with the Azure Government app.
describe('CIPPM365OAuthButton government cloud', () => {
  const GOV_APP_ID = '0a0a0a0a-1111-2222-3333-444444444444'
  let openSpy
  let popup

  beforeEach(() => {
    vi.useFakeTimers()
    vi.stubGlobal('BroadcastChannel', MockBroadcastChannel)
    MockBroadcastChannel.instances.length = 0
    openSpy = vi.spyOn(window, 'open')
    popup = { closed: false, close: vi.fn(), location: null }
    openSpy.mockReturnValue(popup)
    vi.spyOn(globalThis.crypto.subtle, 'digest').mockResolvedValue(new Uint8Array(32).buffer)
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  const listAppId = (data) => getResult({ data })

  it.each([
    ['USGovHigh', 'https://graph.microsoft.us/.default'],
    ['USGovDoD', 'https://dod-graph.microsoft.us/.default'],
  ])('opens the %s sign-in at login.microsoftonline.us with the Azure Government app', async (cloud, scope) => {
    api.get = listAppId({ applicationId: APP_ID, govApplicationId: GOV_APP_ID })
    renderWithTheme(<CIPPM365OAuthButton cloudEnvironment={cloud} scope={scope} />)

    fireEvent.click(authButton())
    await act(async () => {})

    const url = new URL(popup.location)
    expect(url.origin).toBe('https://login.microsoftonline.us')
    expect(url.pathname).toBe('/organizations/oauth2/v2.0/authorize')
    expect(url.searchParams.get('client_id')).toBe(GOV_APP_ID)
    expect(url.searchParams.get('scope')).toBe(scope)
  })

  it('exchanges the code at the government token endpoint and reports the cloud', async () => {
    api.get = listAppId({ applicationId: APP_ID, govApplicationId: GOV_APP_ID })
    const payload = btoa(JSON.stringify({ tid: 'tid-1', aud: 'https://graph.microsoft.us' }))
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ access_token: `h.${payload}.s`, refresh_token: 'r', expires_in: 3600 }),
    })
    vi.stubGlobal('fetch', fetchMock)
    const onAuthSuccess = vi.fn()
    renderWithTheme(<CIPPM365OAuthButton cloudEnvironment="USGovHigh" onAuthSuccess={onAuthSuccess} />)

    fireEvent.click(authButton())
    await act(async () => {})
    const state = new URL(popup.location).searchParams.get('state')
    await act(async () => {
      lastChannel().onmessage({ data: { type: 'auth_code', code: 'abc', state } })
    })

    const exchange = fetchMock.mock.calls.find(([url]) => url === '/api/ExecTokenExchange')
    const body = JSON.parse(exchange[1].body)
    expect(body.tokenUrl).toBe('https://login.microsoftonline.us/organizations/oauth2/v2.0/token')
    expect(body.cloudEnvironment).toBe('USGovHigh')
    expect(body.tokenRequest.client_id).toBe(GOV_APP_ID)
    expect(onAuthSuccess).toHaveBeenCalledWith(expect.objectContaining({ cloudEnvironment: 'USGovHigh' }))
  })

  it('never falls back to CIPP-SAM when the Azure Government app is not configured', () => {
    api.get = listAppId({ applicationId: APP_ID })
    renderWithTheme(<CIPPM365OAuthButton cloudEnvironment="USGovHigh" />)

    expect(screen.getByText(/Azure Government app not configured/)).toBeInTheDocument()
    expect(authButton()).toBeDisabled()
  })

  it('disables sign-in for an unknown cloud', () => {
    api.get = listAppId({ applicationId: APP_ID, govApplicationId: GOV_APP_ID })
    renderWithTheme(<CIPPM365OAuthButton cloudEnvironment="usgovhigh" />)
    expect(authButton()).toBeDisabled()
  })

  it.each(['USGovHigh', 'USGovDoD'])(
    'never starts a device code sign-in for %s, even with autoStartDeviceLogon',
    async (cloud) => {
      api.get = listAppId({ applicationId: APP_ID, govApplicationId: GOV_APP_ID })
      const fetchMock = vi.fn()
      vi.stubGlobal('fetch', fetchMock)
      renderWithTheme(
        <CIPPM365OAuthButton cloudEnvironment={cloud} useDeviceCode autoStartDeviceLogon />
      )
      await act(async () => {})

      expect(screen.getByText(/Device code sign-in is not available/)).toBeInTheDocument()
      expect(screen.getByRole('button', { name: /Login with Microsoft/ })).toBeDisabled()
      expect(fetchMock).not.toHaveBeenCalled()
      expect(openSpy).not.toHaveBeenCalled()
    }
  )

  it('keeps the commercial device code sign-in available', async () => {
    api.get = listAppId({ applicationId: APP_ID, govApplicationId: GOV_APP_ID })
    renderWithTheme(<CIPPM365OAuthButton useDeviceCode />)
    await act(async () => {})
    expect(screen.queryByText(/Device code sign-in is not available/)).not.toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Login with Microsoft/ })).toBeEnabled()
  })

  it('exchanges a commercial code exactly as before and stores the refresh token for the token tenant', async () => {
    api.get = listAppId({ applicationId: APP_ID, govApplicationId: GOV_APP_ID })
    const payload = btoa(JSON.stringify({ tid: 'tid-1', aud: 'https://graph.microsoft.com' }))
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ access_token: `h.${payload}.s`, refresh_token: 'r', expires_in: 3600 }),
    })
    vi.stubGlobal('fetch', fetchMock)
    const onAuthSuccess = vi.fn()
    renderWithTheme(<CIPPM365OAuthButton onAuthSuccess={onAuthSuccess} />)

    fireEvent.click(authButton())
    await act(async () => {})
    const state = new URL(popup.location).searchParams.get('state')
    await act(async () => {
      lastChannel().onmessage({ data: { type: 'auth_code', code: 'abc', state } })
    })

    const exchange = fetchMock.mock.calls.find(([url]) => url === '/api/ExecTokenExchange')
    const body = JSON.parse(exchange[1].body)
    expect(body.tokenUrl).toBe('https://login.microsoftonline.com/organizations/oauth2/v2.0/token')
    expect(body.tokenRequest.client_id).toBe(APP_ID)
    expect(body.tenantId).toBe(APP_ID)
    // the backend treats an explicit Commercial exactly like an absent value
    expect(body.cloudEnvironment).toBe('Commercial')
    const store = fetchMock.mock.calls.find(([url]) => url === '/api/ExecUpdateRefreshToken')
    expect(JSON.parse(store[1].body)).toEqual(
      expect.objectContaining({
        tenantId: 'tid-1',
        refreshtoken: 'r',
        cloudEnvironment: 'Commercial',
        accessToken: `h.${payload}.s`,
        // the partner sign-in is not a direct-tenant sign-in
        directTenant: false,
      })
    )
    expect(onAuthSuccess).toHaveBeenCalledWith(
      expect.objectContaining({ cloudEnvironment: 'Commercial', accessToken: `h.${payload}.s` })
    )
  })

  it('tells the backend a direct-tenant sign-in is one, so it can refuse a partner account', async () => {
    api.get = listAppId({ applicationId: APP_ID, govApplicationId: GOV_APP_ID })
    const payload = btoa(JSON.stringify({ tid: 'tid-1', aud: 'https://graph.microsoft.com' }))
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ access_token: `h.${payload}.s`, refresh_token: 'r', expires_in: 3600 }),
    })
    vi.stubGlobal('fetch', fetchMock)
    renderWithTheme(<CIPPM365OAuthButton onAuthSuccess={vi.fn()} directTenant />)

    fireEvent.click(authButton())
    await act(async () => {})
    const state = new URL(popup.location).searchParams.get('state')
    await act(async () => {
      lastChannel().onmessage({ data: { type: 'auth_code', code: 'abc', state } })
    })

    const store = fetchMock.mock.calls.find(([url]) => url === '/api/ExecUpdateRefreshToken')
    expect(JSON.parse(store[1].body)).toEqual(
      expect.objectContaining({ tenantId: 'tid-1', directTenant: true })
    )
  })

  it('stops without reporting success when the backend refuses to store the refresh token', async () => {
    api.get = listAppId({ applicationId: APP_ID, govApplicationId: GOV_APP_ID })
    const payload = btoa(JSON.stringify({ tid: 'tid-1', aud: 'https://graph.microsoft.us' }))
    const fetchMock = vi.fn(async (url) =>
      url === '/api/ExecUpdateRefreshToken'
        ? {
            ok: false,
            status: 400,
            json: async () => ({ Results: { resultText: 'The stored credentials were not changed.' } }),
          }
        : {
            ok: true,
            status: 200,
            json: async () => ({ access_token: `h.${payload}.s`, refresh_token: 'r', expires_in: 3600 }),
          }
    )
    vi.stubGlobal('fetch', fetchMock)
    const onAuthSuccess = vi.fn()
    const onAuthError = vi.fn()
    renderWithTheme(
      <CIPPM365OAuthButton
        cloudEnvironment="USGovHigh"
        onAuthSuccess={onAuthSuccess}
        onAuthError={onAuthError}
      />
    )

    fireEvent.click(authButton())
    await act(async () => {})
    const state = new URL(popup.location).searchParams.get('state')
    await act(async () => {
      lastChannel().onmessage({ data: { type: 'auth_code', code: 'abc', state } })
    })

    expect(onAuthSuccess).not.toHaveBeenCalled()
    expect(onAuthError).toHaveBeenCalledWith(
      expect.objectContaining({ errorCode: 'refresh_token_refused' })
    )
  })

  it('keeps the commercial sign-in on login.microsoftonline.com with CIPP-SAM', async () => {
    api.get = listAppId({ applicationId: APP_ID, govApplicationId: GOV_APP_ID })
    renderWithTheme(<CIPPM365OAuthButton />)

    fireEvent.click(authButton())
    await act(async () => {})

    const url = new URL(popup.location)
    expect(url.origin).toBe('https://login.microsoftonline.com')
    expect(url.searchParams.get('client_id')).toBe(APP_ID)
  })
})

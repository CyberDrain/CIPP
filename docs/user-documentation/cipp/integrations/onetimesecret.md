# One-Time Secret

One-Time Secret replaces generated passwords with links that can be revealed once. It supports the same CIPP actions as Password Pusher: user creation (including bulk), password resets, JIT admin accounts, and restore tasks.

Use a regional hosted service or a self-hosted instance supporting the [stable v2 API](https://api.onetimesecret.com/doc/api-v2). Legacy instances offering only v1 are not supported.

## Setup

1. Open **CIPP > Integrations > One-Time Secret** and enable the integration.
2. Enter the HTTPS base URL for the region where your account is registered, such as `https://nz.onetimesecret.com`, `https://eu.onetimesecret.com`, or your self-hosted URL. Do not append `/api/v2`. CIPP does not follow redirects when sending secrets.
3. Enter your account email address and API key. CIPP stores the API key through its existing Key Vault integration.
4. Set an expiration from **1 to 168 hours**, or leave it blank for **24 hours**. Your service or account limits may shorten this lifetime or reject the request. A secret is destroyed after its first reveal even if time remains.
5. Optionally set a default passphrase. Recipients need this to reveal their password; share it separately from the link.
6. Save the configuration, then use **Test**. The test creates a link containing harmless test text. Copy and open it to verify the reveal flow; revealing it consumes it.

## Provider selection and failures

If both One-Time Secret and Password Pusher are enabled, **Password Pusher takes priority** for generated passwords, preserving existing behavior. Disable Password Pusher to use One-Time Secret. Each integration's Test button always tests that specific provider.

If the selected service fails, CIPP retains the existing Password Pusher behavior: the operation returns the plain text password. It does not send the password to the other provider as a retry. Check the CIPP logbook under API **OneTimeSecret** and run the integration test to diagnose failures. Error logs exclude API response bodies, passwords, passphrases, and authentication headers.

The default passphrase uses the existing extension configuration storage, like Password Pusher's default passphrase; it is not stored as a separate Key Vault secret.

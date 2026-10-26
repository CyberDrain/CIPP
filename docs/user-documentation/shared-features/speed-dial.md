# Speed Dial

The CIPP speed dial gives you quick access to help, feedback, and troubleshooting from anywhere in the application. It sits as a round button in the lower right corner of your browser window, and opens when you hover over it or click it. Clicking anywhere outside closes it again.

{% hint style="info" %}
On a phone the lower right corner holds the actions for the page you are on, so the speed dial is not shown. **Report Bug**, **Request Feature**, **Join the Discord!**, **Check the Documentation** and **Clear Cache and Reload** move into your account menu instead. **Tutorials**, **License** and **Generate Support File** are available on a larger screen. See [mobile-layout.md](mobile-layout.md "mention").
{% endhint %}

## Options

| Option                  | Description                                                                                                                                                      |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tutorials               | Opens the tutorials list. See [#tutorials](speed-dial.md#tutorials "mention") below.                                                                              |
| Check the Documentation | Opens [docs.cipp.app](https://docs.cipp.app/) in a new tab, at the page matching the CIPP page you are currently on.                                             |
| Join the Discord!       | Opens a new tab to join the [CyberDrain Discord server](https://discord.gg/cyberdrain).                                                                          |
| Request Feature         | Opens a new tab to the GitHub feature request form.                                                                                                              |
| Report Bug              | Opens a new tab to the GitHub bug report form.                                                                                                                   |
| Generate Support File   | Collects what support needs to diagnose a problem into a single file you can download and attach to a ticket. See [#generate-support-file](speed-dial.md#generate-support-file "mention") below. |
| License                 | Opens CIPP's own licence page, showing the GNU Affero General Public License terms.                                                                              |
| Clear Cache and Reload  | Clears CIPP's cached data from your browser and reloads the page. This is especially helpful if you recently updated CIPP and are still seeing an older version. |

{% hint style="info" %}
Feature requests can only be raised by users with an active subscription. Requests from non-subscribers are closed automatically. The form itself sets out the current requirement.
{% endhint %}

## Tutorials

The **Tutorials** option opens a list of guided walkthroughs that highlight parts of the interface and step you through them in place. Search the list to narrow it down, then choose a tutorial to start it.

Your progress is tracked, with a count of how many tutorials you have completed shown at the foot of the list and completed entries marked. A reset control at the top of the dialog clears that progress so the tutorials can be taken again.

## Generate Support File

**Generate Support File** gathers the information support usually has to ask for into one JSON file: the requests CIPP made to its own API, the version, hosting and update details of your instance, and your signed-in identity and the roles you hold. You download the file and attach it to your ticket or Discord thread.

Choose how the requests are captured.

| Option                | Description                                                                                                                                                                              |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Capture This Page** | Reloads the data on the page you are on and captures the requests it makes. Use this where the problem is visible on a single page, such as a table that will not load or a value that looks wrong. |
| **Record Actions**    | Starts recording and closes the dialog so you can reproduce the problem yourself. Use this where the problem only appears after a sequence of steps, or spans more than one page.         |

While a recording is running, a red **Recording** chip sits beside the speed dial. Selecting it reopens the dialog, where **Stop & Generate** ends the recording and builds the file, **Continue Recording** returns you to the page, and **Discard** throws the recording away. Reloading the browser also discards it.

Once the file is ready the dialog reports how many requests were captured and how many of them failed, and **Download** saves it.

### Redaction

**Redact tenant IDs, domains and email addresses** is on by default. With it on, every email address, GUID and tenant domain in the file is replaced before you ever see it: addresses become `user1@redacted.invalid`, tenant domains become `domain1.invalid`, and GUIDs become placeholder GUIDs. The replacement is consistent, so the same value always becomes the same placeholder and support can still follow one user or one tenant through the file without learning who they are. Your own CIPP instance's address is kept, because that identifies the installation rather than a customer.

Turning redaction off produces a file containing real tenant data from the requests that were captured.

{% hint style="warning" %}
Read the file before you send it, particularly with redaction turned off. It contains the responses CIPP received, which can include user names, addresses and tenant identifiers.
{% endhint %}

{% hint style="info" %}
Authentication tokens are removed from every file, whether or not redaction is on. Very large responses are shortened and marked as such, so one oversized page cannot produce a file too big to attach.
{% endhint %}

{% include "../../../.gitbook/includes/feature-request.md" %}

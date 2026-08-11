# GitHub

The GitHub integration lets CIPP work with GitHub repositories, most visibly through the Community Repositories catalog where templates and scripts are browsed, imported, and published. Authentication uses a GitHub Personal Access Token, and the scopes you grant determine how much of the functionality is available.

{% hint style="info" %}
The integration is optional. Without it, CIPP falls back to a built-in shared token that provides read-only access to public community repositories. Configure your own token when you need private or internal repositories, or when you want to publish templates and scripts back to GitHub.
{% endhint %}

## Settings

| Setting                      | Description                                                                                                                                                                                                          |
| ---------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enable Integration           | Turns the integration on, so that CIPP authenticates as your token rather than falling back to the shared read-only one. The token field and the **Test** button remain unavailable until this is enabled and saved. |
| GitHub Personal Access Token | Your GitHub Personal Access Token. Stored securely and masked once saved.                                                                                                                                            |

## Choosing the Right Token Scopes

Grant the narrowest scope that covers what you intend to do.

| Scope              | What it covers                                                                                                                                |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `repo:public_repo` | The minimum required. Reading and writing public repositories, which is enough for browsing and importing from public community repositories. |
| `repo` (full)      | Required for private and internal repositories, and for publishing your own templates and scripts back to GitHub.                             |

{% hint style="warning" %}
Use a classic Personal Access Token rather than a fine-grained one. Fine-grained tokens scope permissions differently, and that difference causes unexpected failures against the endpoints CIPP uses. The **Test** button reports when it detects a fine-grained token, because it cannot read back the granted scopes in that case.
{% endhint %}

See [GitHub's documentation](https://docs.github.com/en/github/authenticating-to-github/keeping-your-account-and-data-secure/creating-a-personal-access-token) for how to create a token and what each scope grants.

## Configuring the Integration

{% stepper %}
{% step %}
### Create the token

Create a classic Personal Access Token in your GitHub account settings, granting the scopes described above. Copy it before leaving the page, as GitHub will not show it again.
{% endstep %}

{% step %}
### Enable the integration

Turn on **Enable Integration**. The token field stays disabled until it is on.
{% endstep %}

{% step %}
### Enter the token

Paste the token into **GitHub Personal Access Token**, then select **Submit** and wait for confirmation that the settings were updated.
{% endstep %}

{% step %}
### Test

Select **Test**. A successful result names the GitHub account CIPP authenticated as, and lists the scopes attached to the token, so you can confirm at a glance whether you have granted enough for what you plan to do.
{% endstep %}
{% endstepper %}

## What the Integration Enables

| Capability                                               | Token requirement                                                                                                            |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Browsing and searching community repositories            | None. Works through the built-in shared token.                                                                               |
| Importing templates and scripts from a public repository | None, though your own token gives you a higher rate limit.                                                                   |
| Adding a private or internal repository to the catalog   | Full `repo` scope.                                                                                                           |
| Publishing templates and scripts to a repository         | Full `repo` scope.                                                                                                           |
| Creating a new repository from CIPP                      | Full `repo` scope, on a token belonging to an account with rights to create repositories in the target user or organization. |

Repositories and their templates are managed on the [community-repos](../../tools/community-repos/ "mention") page rather than here. This page only holds the credentials.

## Reading the Results Banner

Results from **Test** appear in a banner at the top of the page, with two controls common to all integration pages.

| Control          | Description                                                           |
| ---------------- | --------------------------------------------------------------------- |
| View Results     | Opens a table showing the results of the most recent attempt in full. |
| Download Results | Downloads those results as a CSV file.                                |

{% include "../../../../.gitbook/includes/feature-request.md" %}

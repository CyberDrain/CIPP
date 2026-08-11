---
description: Connect to GitHub community repositories for easy template creation!
---

# Catalog

Template sources are GitHub repositories CIPP reads templates from, letting you import configurations shared by the MSP community rather than building each one yourself. This page shows every source registered with your instance, and is where you add, configure and remove them.

{% hint style="info" %}
This page is powered by the GitHub integration. CIPP can populate much of this information even without your own Personal Access Token, but creating repositories and reading private ones requires one. See the [github.md](../../cipp/integrations/github.md "mention") integration page for more.
{% endhint %}

## Action Buttons

{% content-ref url="browse-all-templates.md" %}
[browse-all-templates.md](browse-all-templates.md)
{% endcontent-ref %}

<details>

<summary>Create Repository</summary>

Opens the **Create New Repository** dialog, which creates a new repository on GitHub and registers it as a source in one step. Useful for setting up a private repository to hold your own templates.

| Field           | Description                                                                  |
| --------------- | ---------------------------------------------------------------------------- |
| User / Org      | Whether the repository is created under your own account or an organization. |
| Organization    | The organization to create it under. Only shown when Org is selected.        |
| Repository Name | The name of the new repository.                                              |
| Description     | The repository description.                                                  |
| Private         | Creates the repository as private rather than public.                        |

This button is unavailable unless the GitHub integration is enabled, since creating a repository requires your own Personal Access Token.

</details>

<details>

<summary>Add Source</summary>

Opens the **Add Template Source** dialog, which registers an existing GitHub repository.

| Field                               | Description                                                                                                                                                                                                          |
| ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GitHub repository URL or owner/repo | The repository to add. Either format is accepted, so a pasted GitHub URL works as well as `owner/repo`.                                                                                                              |
| Template Types                      | The kinds of template the repository contains, used to decide which catalogs its templates appear in. Repositories that follow CIPP's folder naming are detected automatically, so this can be left empty for those. |

</details>

## Source Cards

Each registered source is shown as a card carrying its name, its `owner/repo` full name, and its description. Selecting a card opens that source's templates.

Chips below the description show the template types the source provides, capped at four with a **+N more** chip where there are others. Two further chips may appear:

| Chip         | Meaning                                                               |
| ------------ | --------------------------------------------------------------------- |
| Built-in     | A source CIPP ships with. These cannot be removed or retyped.         |
| Write Access | CIPP can push to this repository, so templates can be uploaded to it. |

At the foot of each card, a colored dot and a count show how many templates the source currently provides, green where templates were found and amber where none were. Where the source reports one, the most recent commit message is shown beneath, which is the quickest way to see whether a source is still being maintained.

## Source Actions

The menu on each card carries the actions for that source.

| Action            | Description                                                                                                                               |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| Open on GitHub    | Opens the repository on GitHub in a new tab.                                                                                              |
| Set Upload Branch | Chooses which branch templates are pushed to when uploading. Only shown on sources CIPP has write access to.                              |
| Set Template Type | Changes which template types the source is tagged with, and so which catalogs its templates appear in. Not available on built-in sources. |
| Remove Source     | Unregisters the source. Not available on built-in sources.                                                                                |

{% hint style="info" %}
Removing a source only stops CIPP reading from it. Templates you have already imported are unaffected, and nothing is deleted on GitHub, including private repositories you own.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}

---
description: How to write, structure and submit changes to the CIPP documentation.
---

# Contributing to the Documentation

FOSS ([Free and Open-Source Software](https://en.wikipedia.org/wiki/Free_and_open-source_software)) lives and dies by the contributions of its community, and documentation is the part that most often goes unwritten. If you have spotted a gap, a page that is out of date, or a feature you understand well enough to explain, this page tells you where the docs live, how to write a page that matches the rest of the set, and how to get your change published.

## Where the Documentation Lives

Everything published at [docs.cipp.app](https://docs.cipp.app) is built from the `docs/` folder of the [CyberDrain/CIPP](https://github.com/CyberDrain/CIPP) repository on the **`dev`** branch. GitBook is two-way synced with that branch, so a change merged into `dev` appears on the site, and an edit made in GitBook is committed back to `dev`.

A few consequences worth knowing before you start:

* `dev` is the only branch that matters for documentation. Never open a documentation pull request against `main`.
* Always `git fetch` and start from the current `dev`. GitBook commits to the branch on its own, so your local copy goes stale faster than a normal code branch.
* Images and other assets live in `.gitbook/assets/`, and reusable snippets live in `.gitbook/includes/`, both at the root of the repository rather than under `docs/`.

{% hint style="info" %}
`docs/SUMMARY.md` is the table of contents. A page that is not listed in it is orphaned, so it will not appear in the navigation even though the file exists.
{% endhint %}

## Documentation Style

Use American English for all documentation updates and new content. This includes spelling, grammar, and terminology across user, setup, API, and developer docs.

## How to Contribute a Change

Contributions come in through GitHub, whether you are fixing a typo or writing a page from scratch. The **Edit on GitHub** option on every published page takes you straight to that page's source file in the repository, which is the fastest way to start. Editing in GitBook itself is reserved for maintainers and for collaborators who have been invited to the space.

For a small fix you never have to leave the browser. Follow the edit option, use the pencil icon on GitHub, and GitHub forks the repository and opens the pull request for you. For a new page, a set of related pages, anything that moves or renames files, or a change that touches `docs/SUMMARY.md`, work locally instead:

{% stepper %}
{% step %}
### Fork and branch

Fork [CyberDrain/CIPP](https://github.com/CyberDrain/CIPP), then create a branch from `dev`.
{% endstep %}

{% step %}
### Write the page

Follow the structure and style rules below. Keep the change to documentation only, as mixing `docs/` changes into a code pull request makes both harder to review.
{% endstep %}

{% step %}
### Add it to the navigation

Add or update the entry in `docs/SUMMARY.md`, in the position the page should appear in the sidebar.
{% endstep %}

{% step %}
### Open the pull request against `dev`

Use a [Conventional Commits](https://www.conventionalcommits.org/) title, for example `docs(identity): document the Users page`. Say in the description which pages were added, moved or renamed.
{% endstep %}
{% endstepper %}

{% hint style="warning" %}
Renaming or moving a page changes its published URL, which breaks existing links and bookmarks. If you do not search the remaining documentation for references, call it out in the pull request so maintainers can decide whether a redirect is needed.
{% endhint %}

## Choosing Where a Page Goes

The documentation is split into a small number of top-level sections:

| Section               | What belongs there                                                                        |
| --------------------- | ----------------------------------------------------------------------------------------- |
| `setup/`              | Installing, configuring, maintaining and implementing CIPP.                               |
| `user-documentation/` | One page per screen in the CIPP interface, plus shared behavior under `shared-features/`. |
| `api-documentation/`  | Working with the CIPP API.                                                                |
| `troubleshooting/`    | Diagnosing and fixing problems.                                                           |
| `dev-documentation/`  | Developing CIPP itself, including this page.                                              |

### The path of a user documentation page must mirror the UI route

This is functional, not cosmetic. The **Check the Documentation** entry in the in-app speed dial builds its link by appending the current router path to `https://docs.cipp.app/user-documentation`, so a page filed anywhere else is a broken link from inside the product.

Derive the path from `frontend/src/pages/**`, never from a tidier-looking grouping:

* A route directory's `index.js` becomes `<name>.md`, or `<name>/README.md` when the route also has sibling pages.
* Sibling route files such as `add.jsx`, `edit.jsx` or `policy.jsx` become `add.md`, `edit.md` and `policy.md` in that folder.

### Pages versus drawers

A sub-page is only warranted when the button in the interface **navigates to a routed page**. Buttons that open a drawer or off-canvas panel never leave the list page, so their fields are documented inside the parent page rather than as a page of their own. Decide this from the frontend: a routed page has a file under `frontend/src/pages/**` and the parent triggers it with `link:` or `href=`, while a drawer is a `Cipp*Drawer` component imported into the parent with no matching route file.

When a routed page does exist, reference it from the parent:

```
{% content-ref url="add.md" %}
[add.md](add.md)
{% endcontent-ref %}
```

### Moving a page breaks four other things

If you move or rename a file, check all of these before opening the pull request:

1. The `{% include %}` path, whose depth is counted in directories from the file's folder up to the repository root.
2. Relative links inside the moved file, especially cross-section ones such as `../../identity/...`.
3. Inbound links from other pages. Grep the whole `docs/` tree for the old filename.
4. The entry in `docs/SUMMARY.md`.

## Finding Out What a Page Actually Does

Documentation that guesses is worse than no documentation. Before describing a screen, read the code behind it:

* The screen itself is at `frontend/src/pages/<route>/index.js`. It is often only wiring, so follow the components it imports for the real logic.
* On a list page, searching that file for `simpleColumns`, `label:`, `link:`, `hideBulk`, `offCanvas`, `cardButton`, `filterName` and `condition` surfaces the columns, actions, bulk behavior and drawers in a single pass.
* For what an action does once it is clicked, read the matching `Invoke-<Name>.ps1` in the API.

Never guess what a field means. If you cannot ground a statement in the code or in vendor documentation, leave it out and flag it in the pull request instead.

## Page Anatomy

A user documentation page is laid out like this:

* An H1 with the page title, matching the name of the screen.
* An unheaded introduction paragraph saying what the page is for and when someone would use it.
* H2 headings for each section.
* The feature request include as the very last line, with no `***` before it, because the include brings its own divider.

```
{% include "../../../.gitbook/includes/feature-request.md" %}
```

Pages under `dev-documentation/` do not carry the include.

### List and table pages

Use this order: introduction, `## Action Buttons`, `## Filters`, `## Table Details`, `## Table Actions`. Action buttons are documented in a `<details>` block each, with the button name as the `<summary>` with the exception of actions that lead to a separate page. Those use the page link reference:

```
{% content-ref url="add.md" %}
[add.md](add.md)
{% endcontent-ref %}
```

### Form and settings pages

Use one H2 per card on screen, with the card names reproduced exactly as they appear. Under each, describe the fields in a `| Setting | Description |` or `| Field | Description |` table, grouped under `**Bold**` mini-headings where the form itself is divided into sections.

### Multi-step processes

Use `{% stepper %}` and `{% step %}` GitBook blocks rather than a numbered list.

## Writing Style

**Write about outcomes, not implementation.** Describe what happens for the person clicking the button. "Blocks the user from signing in", not "calls the sign-in state endpoint". Backend mechanics stay out of user documentation: internal function names, cmdlet sequences, cache windows, queue and orchestrator detail, merge logic and role strings.

**Be direct.** Present tense, third person, and "you" when the reader is doing something. No hedging, no filler, and do not open a section by restating its heading.

**Use American English in prose:** license as a noun and license as a verb, organization, authorize, behavior, customize, catalog, analyze, synchronize. Vendor product names and on-screen labels are reproduced **verbatim**, including American spelling, so it is "Microsoft 365 admin center" and "Partner Center". Mirror the interface, do not tidy it up.

**Other conventions:**

* Oxford comma.
* Write "for example", never "e.g." or "i.e.".
* No em dashes anywhere. Restructure with commas, colons, brackets or two sentences.
* **Bold** for button and UI labels, `backticks` for API values, cmdlets and literal settings.

### What to leave off a page

The following are covered centrally in [table-features.md](../user-documentation/shared-features/table-features.md "mention") and should not be repeated:

* Per-page All Tenants notes, unless the page genuinely behaves differently, such as queueing a background job.
* Explanations of Live and Cached data.
* General filtering, searching, exporting and column-picker behavior. Filter _presets_ defined by a page are documented, the mechanism is not.
* Sentences describing where the page sits in the navigation.

### Bugs do not go on pages

If you find a defect, a dead route or behavior that looks wrong, raise a [bug report](https://github.com/CyberDrain/CIPP/issues/new?template=bug.yml) rather than documenting the fault on the page. Mention the issue number in your pull request so a maintainer can decide whether the page should describe the current behavior or the intended behavior.

## Tables

### Table Details

If the grid is essentially the raw return of a documented upstream object, do not hand-write a column table. Point at the upstream documentation instead, which stays correct as that object changes:

* Graph: The properties returned are for the Graph resource type `user`. For more information on the properties please see the Graph documentation.
* PowerShell: The properties returned are for the Exchange Online PowerShell command `Get-Mailbox`. For more information on the command please see the Microsoft documentation.

Write a descriptive `| Column | Description |` table only when there is no documented upstream object, or when CIPP joins, computes, renames or derives any of the columns. The test: would a reader following the link find every column explained? If not, write the table.

Column names in the first cell are the friendly display name shown in the interface, in Title Case with spaces, never raw camelCase and never in backticks. Do not document the Tenant or Cache Timestamp columns, as they are added automatically in All Tenants and cached modes.

### Table Actions

Table Actions is always an HTML table, because the third column has to render as checkboxes:

```html
<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit User</td><td>Opens the edit form for the selected user.</td><td>false</td></tr></tbody></table>
```

Values are a bare `true` or `false`, never a tick glyph. Inside cells use `<code>` for literal values and `<strong>` for labels, as markdown formatting does not render there, and escape ampersands as `&#38;`.

An action offers a bulk equivalent if, and only if, it has no `link` and no `hideBulk: true`. Neither `multiPost` nor `showInActionsMenu` affects this, and an action with a `condition` still counts as available.

Conditions **disable** an action, they do not hide it, so describe a conditional action as **greyed out** and put the condition in the description rather than in the checkbox column.

Where the page has a row flyout, the last row of the table is always, word for word:

```html
<td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td>
```

Leave the row out entirely if the page has no flyout.

## GitBook Blocks

| Block                          | When to use it                                             |
| ------------------------------ | ---------------------------------------------------------- |
| `{% hint style="info" %}`      | A clarification.                                           |
| `{% hint style="warning" %}`   | A gotcha, or a caveat about what something really means.   |
| `{% hint style="danger" %}`    | Destructive or high-risk actions.                          |
| `{% hint style="success" %}`   | A tip for doing something at scale, usually via Standards. |
| `<details>` / `<summary>`      | Action buttons and drawers.                                |
| `{% stepper %}` / `{% step %}` | Ordered processes and wizards.                             |
| `{% content-ref %}`            | Linking to a documented sub-page.                          |
| `{% code %}`                   | Code and configuration samples.                            |

Cross-link other pages with GitBook mention syntax, using the filename as the link text:

```
[table-features.md](../../../shared-features/table-features.md "mention")
```

Inside an HTML cell, use `<a data-mention href="table-features.md">table-features.md</a>` instead.

## Reusable Content

Shared snippets live in `.gitbook/includes/` at the root of the repository. Only three are in use: `feature-request.md`, which closes every user documentation page, `intune-actions.md` and `live-cached-page-action.md`.

* Never reword the text of an include on a consuming page.
* Never put a `***` divider before an include that already carries one.
* Never start a reusable content file with an H1. GitBook's importer treats a leading H1 as the snippet's title and strips it from the body. Lead with a `***` divider if the snippet needs a heading.
* `live-cached-page-action.md` is retired in favor of `table-features.md`. Do not add it to new pages.

## Before You Submit

* The page is listed in `docs/SUMMARY.md`.
* For user documentation, the file path matches the UI route exactly.
* Every claim is grounded in the code or in vendor documentation.
* Prose is American English, product names and UI labels are verbatim, and there are no em dashes.
* Relative links and the `{% include %}` path resolve from the file's actual location.
* The page ends with the feature request include, with no divider before it.
* The pull request targets `dev` and has a Conventional Commits title.

{% include "../../.gitbook/includes/feature-request.md" %}

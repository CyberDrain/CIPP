# Shadow AI Discovery

This page lists the AI tools in use in a tenant, so you can discover unapproved tools known as shadow AI.

The date the tenant's data was last collected is shown at the top of the page. If nothing has been collected yet, the page prompts you to run **Sync data** first.

## Action Buttons

<details>

<summary>Executive Shadow AI Report</summary>

Generates an executive summary of the shadow AI in the tenant, for ease of sharing with client management. Optionally select the sections you wish to include before clicking the download PDF button; a live preview of the branded PDF updates as you toggle them. The available sections are Cover Page, Executive Summary, Infographic Pages, Understanding Shadow AI, Risk Levels & Distribution, Sanctioned Tools, AI Software (Intune), AI Applications (Entra), and Recommendations; at least one section must remain enabled. The button is unavailable until the tenant's data has been synced.

</details>

<details>

<summary>Sync data</summary>

Collects fresh device and application data for the tenant. The report updates once the sync completes.

</details>

## Overview

The overview contains several information cards that you can use to get a view of the tenant's shadow AI.

### Info Cards

* **AI Tools Detected**: The number of distinct AI tools found in the tenant across both the device (Intune) and identity (Entra) sources.
* **Device Installs**: The number of device installs for AI tools. This is total installs across the Intune fleet so one app can be installed multiple times.
* **AI Apps in Entra**: The number of AI applications seen in Entra.
* **High-Risk AI Tools**: The number of distinct tools rated High risk, after sanction adjustment.

### Data Cards

#### AI Tools by Category

Shows the tools by category. The categories are:

* **AI Assistant**: general-purpose chat (ChatGPT, Claude, Gemini, Copilot, Perplexity, DeepSeek, Grok). The "paste anything into a box" tools.
* **AI Coding**: assistants and agentic editors (Copilot, Cursor, Cline, Devin, Replit, v0, Bolt, Lovable, Aider).
* **AI Agent & Automation**: autonomous agents and LLM-wired workflow platforms (AutoGPT, CrewAI, Manus, Lindy, n8n, Zapier, Make). Often carry standing OAuth grants into mailboxes/CRMs.
* **AI Image & Design**: generation/editing (Midjourney, Stable Diffusion, DALL-E, Firefly, Canva, ComfyUI, Remove.bg).
* **AI Video & Audio**: video, TTS, and voice cloning (Sora, Synthesia, HeyGen, Runway, Descript, ElevenLabs, CapCut, Suno).
* **AI Meeting Notetaker**: recorders/transcribers with auto-join bots (Otter, Fireflies, Fathom, tl;dv, Granola). Heavy recording-consent angle.
* **AI Writing & Translation**: writing aids, paraphrasers, translation (Grammarly, Jasper, QuillBot, Wordtune, DeepL, Writer).
* **AI Email**: AI email clients/assistants that take mailbox access (Fyxer, Superhuman, Shortwave, Lavender).
* **AI Search & Research**: answer engines and document Q\&A (NotebookLM, Glean, Phind, ChatPDF, AskYourPDF).
* **AI Presentation & Productivity**: deck/note builders plus AI browser sidebar extensions (Gamma, Tome, Notion, Mem, Monica, Sider, Merlin, MaxAI).
* **Local AI Runtime**: locally-run/self-hosted model tooling (Ollama, LM Studio, GPT4All, Jan, Open WebUI, LocalAI). On-device data but ungoverned.
* **AI Platform & API**: model providers, API aggregators, dev frameworks, cloud ML (Azure OpenAI, Vertex, Bedrock, Hugging Face, OpenRouter, Groq, LangChain).
* **AI Business Apps**: vertical SaaS with embedded AI for sales/HR/legal/support/data (Gong, Apollo, Harvey, Spellbook, HireVue, Julius, Chatbase).
* **AI Companion Chatbot**: persona/roleplay/adult chat (Character.AI, Candy.AI, Janitor AI, Crushon, FlowGPT). No business use; these are HR/policy findings.
* **AI-Capable Editor**: not AI itself, listed for visibility as the host for AI extensions (VS Code, JetBrains AI).

#### Top AI Tools

This chart shows you the top eight AI tools in use, ranked by combined footprint (device installs plus 7-day active users). There are two ways to view this chart:

* **By installations**: The summed Intune device count per tool.
* **By users**: The summed 7-day sign-in activity count per tool.

#### AI Tool Risk Distribution

Shows the risk distribution of the AI tools in the tenant.

{% hint style="info" %}
Note that this risk distribution is adjusted for sanctioning. See the sanctioning action in the [#ai-applications-in-entra-table](shadow-ai.md#ai-applications-in-entra-table "mention") section.
{% endhint %}

Risk Categorisation:

* **High** (red, 36 tools): Default/common usage exfiltrates sensitive data with no contractual protection or is inherently disqualifying. Four rough sub-patterns: consumer accounts that train on input (ChatGPT free/Plus, Grok); foreign-jurisdiction data residency (DeepSeek, Qwen, Kimi, CapCut, and Manus, all China-based); autonomous agents with broad standing access (AutoGPT, Devin, CrewAI, Lindy, Fyxer's full-mailbox grant); exfiltration-as-the-product or policy violations (ChatPDF, Julius, Chatbase, Otter/Fireflies meeting bots, Character.AI and other companion chatbots, public-by-default builders like Replit/Lovable/Bolt/v0, and broad page-reading extensions like Monica/Sider/Merlin/MaxAI).
* **Medium** (amber, 118 tools): The default bucket. Legitimate tools that are fine on business/enterprise tiers but land here because discovery typically finds the free/personal-account version, sending data to a vendor cloud under consumer terms without the catastrophic exposure of the High patterns. Most coding assistants, notetakers, creative tools, and API platforms sit here.
* **Low** (blue, 12 tools): contractually safe by design. Enterprise services governed by the org's own tenant/subscription/terms (Azure OpenAI, Vertex, Microsoft Copilot with commercial data protection, NotebookLM under Workspace, Adobe Firefly, JetBrains AI, Writer, Hugging Face, Moveworks, Jan). Worth visibility, low data risk.
* **Informational** (green, 8 tools in-catalog, plus any sanctioned): not really shadow AI: mainstream business software listed only because it has embedded AI (Canva, Notion, Coda, Databricks, Salesforce Einstein, ServiceNow Now Assist, Atlassian Rovo), AI-capable editors (VS Code), and anything you've marked Company Sanctioned for the tenant, since that override forces this level.

## AI Software on Managed Devices (Intune) Table

Lists the AI software found on the tenant's Intune-managed devices, which is the view of what is physically running on endpoints. One row covers one AI tool, however many versions or installer variants of it Intune reports, with its category, risk, and the devices it is installed on. The table is empty when no installed software matches a known AI tool, or when the tenant's device data has not been collected yet.

Preset filters are available from the **Filters** button for **Sanctioned**, **Unsanctioned**, and **High Risk** rows. Clicking a row (or using the More Info action) opens a detail panel for the matched tool, showing its description, an explanation of why it carries its catalog risk rating, its sanction status, its key properties, and the list of devices it is installed on.

### Table Details

| Column      | Description                                                                                                                                                                                      |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Application | The application names as Intune reports them, for example "Copilot, Microsoft.Copilot".                                                            |
| AI Tool     | The AI tool the application was recognized as, for example "Cursor (User)" is listed as Cursor.                                                    |
| Category    | The kind of AI tool it is, for example AI Coding, AI Assistant, or AI Meeting Notetaker.                                                           |
| Risk        | The risk level for the tool. Reads `Informational` while the tool is marked as company sanctioned for the tenant.                                  |
| Status      | Whether the tool is `Sanctioned` or `Unsanctioned` in this tenant.                                                                                 |
| Publisher   | The software publisher Intune reports.                                                                                                            |
| Platform    | The operating systems the tool was found on, showing `Unknown` where Intune does not report one.                                                   |
| Version     | The versions of the tool found across the tenant's devices.                                                                                       |
| Devices     | The devices the tool is installed on, with the assigned user, platform, and OS version for each.                                                   |

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Mark as Company Sanctioned</td><td>Greyed out on a tool that is already sanctioned. Marks the tool sanctioned for the tenant so <strong>Risk</strong> reports as <code>Informational</code> and <strong>Status</strong> becomes <code>Sanctioned</code>. Refetches the report so cards, charts, and both tables update.</td><td>true</td></tr><tr><td>Remove Company Sanctioned Status</td><td>Greyed out on a tool that is not sanctioned. Removes the sanction so the catalog risk level applies again and <strong>Status</strong> returns to <code>Unsanctioned</code>. Refetches the report so cards, charts, and both tables update.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

## AI Applications in Entra Table

Lists the AI applications users have consented to in Entra ID, which is the view of what has been authorized to reach tenant data regardless of whether anything is installed on a device. Each row shows the tool, its category and risk, the permissions it was granted, and how much it has been used recently.

{% hint style="info" %}
The sign-in columns need Entra ID P1 and read `0` without it.
{% endhint %}

Preset filters are available from the **Filters** button for **Sanctioned**, **Unsanctioned**, and **High Risk** rows. Clicking a row (or using the More Info action) opens a detail panel for the matched tool, showing its description, an explanation of why it carries its catalog risk rating, its sanction status, its key properties, the OAuth permissions granted, and the per-user sign-in activity from the last 7 days.

### Table Details

| Column                | Description                                                                                                                                          |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Application           | The name of the enterprise application as it appears in the tenant.                                            |
| AI Tool               | The AI tool the application was recognized as.                                                                 |
| Category              | The kind of AI tool it is, for example AI Assistant, AI Agent &#38; Automation, or AI Email.                    |
| Risk                  | The risk level for the tool. Reads `Informational` while the tool is marked as company sanctioned.             |
| Status                | Whether the tool is `Sanctioned` or `Unsanctioned` in this tenant.                                             |
| Application ID        | The application's client ID.                                                                                   |
| Approved Permissions  | The permissions users have granted the application, listed individually.                                       |
| Sign-ins (7 Days)     | How many times anyone signed in to the application in the last 7 days.                                         |
| Active Users (7 Days) | How many different people signed in to the application in the last 7 days.                                     |
| First Consented       | When the application first appeared in the tenant, which is the best available indication of when it was first approved. |

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Mark as Company Sanctioned</td><td>Greyed out on a tool that is already sanctioned. Marks the tool sanctioned for the tenant so <strong>Risk</strong> reports as <code>Informational</code> and <strong>Status</strong> becomes <code>Sanctioned</code>. Refetches the report so cards, charts, and both tables update.</td><td>true</td></tr><tr><td>Remove Company Sanctioned Status</td><td>Greyed out on a tool that is not sanctioned. Removes the sanction so the catalog risk level applies again and <strong>Status</strong> returns to <code>Unsanctioned</code>. Refetches the report.</td><td>true</td></tr><tr><td>Application Users</td><td>Opens a side drawer listing the application's per-user sign-in activity over the last 7 days: user principal name, display name, sign-in count, and last sign-in time. The data depends on the same Entra ID P1 sign-in enrichment.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../.gitbook/includes/feature-request.md" %}

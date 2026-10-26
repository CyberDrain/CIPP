# Create New Template

This page is used to create a new SharePoint provisioning template, or to edit or copy an existing one. A template defines one or more site templates, each of which provisions either a SharePoint site or a Microsoft Team, along with the document libraries and permissions to apply and, for a Team, any extra channels and folders. Templates can later be deployed to your tenants to provision sites in a consistent way. The page opens in one of three modes depending on how you reach it: **Create** a new template, **Edit** an existing template in place, or **Copy** an existing template into a new one. When copying, the name is pre-filled with a "(Copy)" suffix and saving creates a separate template rather than overwriting the original.

## Template Settings

These settings apply to the template as a whole.

| Setting                            | Description                                                                                                                                                        |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Template Name                      | The name for the template. Required.                                                                                                                               |
| Create groups if they do not exist | When enabled, any groups referenced by the template's permissions that do not already exist in the target tenant are created as security groups during deployment. |
| Skip if exists                     | When enabled, if a site or team with the same name already exists in the target tenant it is left untouched, and no channels, libraries, folders or permissions are applied to it. |

## Site Templates

The Site Templates section is a card canvas where you define each site the template should provision. Add a site using one of the two buttons on the **Add New Site Template** card, **SharePoint** or **Teams**, which sets that entry's site type. There is no limit on the number of site templates, and any card can be removed from its options ("...") menu.

Each site template has:

* **A name**, entered in the card header, which becomes the name of the provisioned site or team.
* **A site type**, either a SharePoint site or a Microsoft Team.
* **A mandatory site-level permission object.** Every site template must have at least one root-level permission grant. Until it does, the card is outlined in red and the Save button stays disabled.
* **One or more document libraries**, described below.
* **Channels and folders**, for a site template that deploys as a Microsoft Team, described below.

On a Microsoft Team card, the body is split into **Libs**, **Channels** and **Folders** tabs, each showing how many entries it holds. A SharePoint card shows its document libraries only.

Further per-card options are reached from each card's options ("...") menu and are described in the following sections.

### Site type

Each site template provisions either a SharePoint site or a Microsoft Team. You choose the type when you add the card, and can change it afterwards with **Change Site Type** on the card's menu. The card's icon reflects the chosen type. When a template-wide override is active, the per-card type is locked (see below).

### Overriding the site type for all sites

The Site Templates section has its own actions ("...") menu containing **Override site types…**. This opens a dialog where you can turn on **Override site type for all sites** and choose a single **Site type**. While the override is on, every site in the template deploys as that one type, ignoring each card's own site type, and the per-card Change Site Type option is disabled until you clear the override. A caption in the section header indicates when the override is active.

### Site language

For a site template that deploys as a SharePoint site, **Site Language** on the card menu sets the language used when the site is created. Leave it on **Tenant default** to follow each target tenant's SharePoint root site language at deployment, or choose a specific language from the list. This option is not shown for Microsoft Team site templates.

### Create as

For a SharePoint site, **Create as** on the card menu chooses the kind of site: a **Team site**, which is a collaboration workspace, or a **Communication site**, which is for publishing such as an intranet or news. This applies only when the card deploys as a SharePoint site and is ignored for Microsoft Teams.

## Document Libraries

Within each site template card, select **Add Library** to add a document library. Each library has a name. From a library's options ("...") menu you can configure unique permissions for that library; a lock icon marks any library that carries its own permissions. A library with no unique permissions inherits the permissions of its site template.

The **Add Column** and **Manage Metadata** options in the library menu are placeholders and are not yet available; columns and metadata can be added to the deployed libraries later.

## Channels

On a Microsoft Team card, the **Channels** tab lists the channels to create in the Team in addition to its default General channel. Select **Add Channel** to add one, then set it up on its row.

| Field        | Description                                                                                                                                                                  |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Channel name | The name of the channel. Required, and cannot be `General`, which every Team already has.                                                                                    |
| Channel type | Set with the icon next to the name, which cycles through **Public channel**, **Private channel** and **Shared channel** each time you select it. New channels start as public. |
| Layout       | Set with the second icon, which switches between **Posts layout**, the traditional posts and replies, and **Chat layout**, a chat-style thread. New channels start with posts. |

A channel is removed with **Remove Channel** on its options ("...") menu.

When the template is deployed, each channel is created in the new Team with the type and layout you chose. Private and shared channels have the **Site / Team Owner** chosen at deployment as their only member. If the Team already has a channel with the same name, that channel is kept as it is and no new one is created.

## Folders

On a Microsoft Team card, the **Folders** tab lists folders to create at the top of the Team's Documents library, next to the General channel's folder. Select **Add Folder** to add one and enter its name. The name is required and cannot be `General`. A folder is removed with **Remove Folder** on its options ("...") menu.

When the template is deployed, each folder is created in the new Team's Documents library. A folder that already exists with the same name is kept as it is.

Channels and folders apply only to site templates that deploy as a Microsoft Team. If a card is changed to a SharePoint site, or the site-type override deploys every site as SharePoint, its channels and folders are not deployed and are left out of the Quick Stats counts. If an individual channel or folder cannot be created, the failure is shown in the deployment progress and the rest of the site's channels, libraries and folders are still created.

## Permissions

Permissions are configured as permission objects at two levels: on a site template (site-level, mandatory) and on individual libraries (optional). Both use the same editor, and each entry pairs a group with a permission level.

| Field              | Description                                                 |
| ------------------ | ----------------------------------------------------------- |
| Group Display Name | The display name of the group to grant access to. Required. |
| Permission Level   | The level of access to grant the group. Required.           |

Groups are referenced by display name only. During deployment the name is matched against each target tenant, so the same template can be deployed anywhere without editing. Enable **Create groups if they do not exist** in Template Settings to have any missing groups created automatically.

The available permission levels are SharePoint's built-in levels:

| Permission Level | Access granted                                         |
| ---------------- | ------------------------------------------------------ |
| Read             | View pages and items, and download documents.          |
| Contribute       | View, add, update, and delete items.                   |
| Edit             | Contribute access plus the ability to manage lists.    |
| Design           | Edit access plus the ability to approve and customise. |
| Full Control     | Full administrative control.                           |

## Quick Stats

A Quick Stats panel beside the builder shows live counts as you build the template.

| Statistic            | Description                                                           |
| -------------------- | --------------------------------------------------------------------- |
| Total Site Templates | The total number of site templates in the template.                   |
| SharePoint Templates | How many site templates will deploy as SharePoint sites.              |
| Teams Templates      | How many site templates will deploy as Microsoft Teams.               |
| Libraries Defined    | The total number of document libraries across all site templates.     |
| Channels Defined     | The total number of channels across site templates that deploy as Microsoft Teams. |
| Folders Defined      | The total number of folders across site templates that deploy as Microsoft Teams.  |
| Permission Grants    | The total number of permission grants across all sites and libraries. |

The SharePoint and Teams counts respect the site-type override, so they always reflect what will actually be deployed.

## Saving

Select **Save Template** to store the template. Save only becomes available once the template is valid: a template name is set and every site template has a name, at least one root-level permission, and a name for every library, and every channel and folder on a Microsoft Team card has a name other than `General`. When something is missing, an information icon next to the Save button lists exactly what needs fixing. Saving a new template or a copy creates a new template, while saving an edit updates the existing template in place. You are then returned to the SharePoint Templates list.

{% include "../../../../.gitbook/includes/feature-request.md" %}

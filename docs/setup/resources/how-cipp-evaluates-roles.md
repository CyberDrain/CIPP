---
description: How CIPP decides a user's effective permissions when they hold multiple roles
---

# How CIPP Evaluates Roles

CIPP assigns access through **built-in roles** and **custom roles**, and a single user can end up holding several of them at once — especially when roles are mapped to Entra ID groups and a user is a member of more than one group. This page explains, in plain terms, how those roles combine into the permissions a user actually gets.

For instructions on _creating_ roles and mapping them to Entra groups, see [Adding Users and Managing Roles](../setting-up-cipp/roles.md).

## The mental model

> **Built-in roles are the ceiling. Custom roles are an explicit allow-list.**

* A **built-in role** (`readonly`, `editor`, `admin`, `superadmin`) sets the **maximum** a user can ever do.
* A **custom role** is an explicit list of allowed permissions, scoped by tenant and endpoint. Paired with a built-in role it **narrows** that ceiling; used on its own it grants **exactly what it defines** — no more, no less.

Everything below follows from those two ideas.

## Built-in roles: highest wins

Built-in roles rank from least to most privileged:

`readonly` → `editor` → `admin` → `superadmin`

If a user is a member of several Entra groups that map to **different built-in roles, they do not add together — the single highest role wins.** A user who is both `editor` and `readonly` is simply an `editor`; the `readonly` membership contributes nothing.

| Built-in role | Effective access                                            |
| ------------- | ----------------------------------------------------------- |
| `readonly`    | Read/list only. No settings, no admin.                      |
| `editor`      | Read **and** write, except system settings and Standards.   |
| `admin`       | Everything except a small set of super-admin-only settings. |
| `superadmin`  | Everything, including high-privilege settings.              |

{% hint style="warning" %}
**`admin` and `superadmin` ignore custom roles entirely.** If _any_ group grants a user `admin` or `superadmin`, they receive the full built-in permission set and every custom role on that user is disregarded. You cannot use a custom role to restrict an admin — assign `editor` or `readonly` instead and filter from there.
{% endhint %}

## Custom roles: an explicit allow-list

A custom role is a hand-built list of permission categories — each set to `None`, `Read`, or `Read/Write` — optionally scoped to specific tenants (Allowed/Blocked Tenants) and with specific endpoints blocked (Blocked Endpoints).

{% hint style="warning" %}
**Any permission category you do not explicitly set is a deny.** An unset category is treated exactly as if you had selected `None`: the user is denied that permission. To let a user keep a capability, you must set that category to `Read` or `Read/Write` in the custom role — leaving it blank removes it.
{% endhint %}

How a custom role behaves depends on whether the user **also** holds a built-in role.

### With a base role (`editor` or `readonly`)

The built-in role sets the ceiling and the custom role **narrows it down**:

* The user can do only what the base role allows **and** the custom role explicitly grants.
* A custom role can never raise a user **above** the ceiling. Granting `Read/Write` to a `readonly` user still results in read-only access, because `readonly` is the ceiling.
* Tenant and endpoint scoping from the custom role applies on top.

### Without a base role (custom roles only)

If the user has **only** custom roles and no built-in role, the custom roles apply **on their own**:

* Their access is exactly what the custom role explicitly grants — nothing more, nothing less.
* There is no built-in ceiling, so base-role exclusions (such as system settings or Standards) do **not** apply. A custom role grants precisely what is defined in it, so scope these roles carefully.

### Multiple custom roles on one user

If a user holds more than one custom role, their granted permissions are **combined — a union, most permissive wins**. If they also hold a base role, that ceiling still caps the combined result.

{% hint style="warning" %}
Tenant scope is evaluated **per custom role**, not pooled across them. For any single action, one custom role must grant **both** the required permission **and** access to the target tenant. A user cannot borrow the permission from one custom role and the tenant access from another.
{% endhint %}

### Tenant groups in a custom role

A custom role without unrestricted tenant access, meaning anything other than **Allowed Tenants** set to `AllTenants` with nothing in **Blocked Tenants**, reaches a tenant group only when that group is named in its **Allowed Tenants**. This applies to picking the group in the tenant selector and to assigning standards, alerts or scheduled tasks to it. Editing a standards template that already targets a group the user's roles do not name is refused in the same way.

* `AllTenants` alongside a list of blocked tenants does not cover any tenant group. Name each group the role needs.
* Adding every tenant in a group to **Allowed Tenants** does not cover the group either. The group itself has to be listed.
* A named group is refused if any of its tenants is in **Blocked Tenants** on the same role. Remove the overlap from one list or the other.
* The tenant selector only lists the groups a user's roles name.

As with single tenants, one custom role has to grant both the permission an action needs and the group.

When a group is refused, the message says why:

| Message | What to change |
| ------- | -------------- |
| Your roles don't include the tenant group '_name_'. Ask an admin to add it to one of your roles. | Add the group to **Allowed Tenants** on a custom role that also grants the permission. |
| Your role '_role_' excludes a tenant in the tenant group '_name_'. | The role names the group, but one of the group's tenants is in its **Blocked Tenants**. |
| You can view the tenant group '_name_' but not change it. | A role names the group, but only grants read access for this area. |
| Your roles include the tenant group '_name_', but not the permission this action needs there. | The role that names the group does not grant this area at all. |
| Your roles don't allow viewing a tenant group. Pick a tenant instead, or ask an admin to change your roles. | **Block tenant groups in the tenant selector** is switched on for the user's role. |
| This view doesn't support tenant groups. Pick a tenant or All Tenants. | The page cannot show a tenant group. Pick a single tenant or All Tenants instead. No role change helps. |

### A tenant scope that resolves to no tenants

A custom role's tenant scope can end up covering nothing at all. The usual causes are a role whose Allowed Tenants are all named again under Blocked Tenants, because a blocked tenant always wins over an allowed one, and a role scoped to a tenant group that currently resolves to no tenants. A user whose only custom roles have since been deleted ends up in the same position.

A role in that state reaches no tenant's data at all, whatever API permissions it holds. The tenant selector comes back empty, All Tenants pages show nothing, and reports drawn from cached data are empty too. A scope that grants nothing is treated as nothing rather than as everything.

{% hint style="info" %}
This is usually reported as CIPP showing no data rather than as an access problem, because nothing on screen says the tenant scope is empty. Check Allowed Tenants and Blocked Tenants on every custom role the user holds, and the membership of any tenant group either list names, before looking anywhere else.
{% endhint %}

## Worked examples

### Example 1 — Built-in roles only

Jane is a member of two Entra groups:

* `CIPP-Editors` → mapped to `editor`
* `CIPP-Read` → mapped to `readonly`

**Result:** the higher role wins, so Jane is an **editor**. The `readonly` membership changes nothing.

### Example 2 — Built-in role + custom role

Mark is a member of two Entra groups:

* `CIPP-Editors` → mapped to `editor`
* `CIPP-Helpdesk` → mapped to a custom role that grants **Identity: Read/Write** only, with **Allowed Tenants = Contoso**

**Result:** `editor` sets the ceiling (read/write everything except settings and Standards). The custom role filters that down to **only Identity read/write**, and only for **Contoso**. Net effect: Mark can manage users in Contoso and nothing else.

If Mark were removed from `CIPP-Editors`, the custom role would then apply **on its own** — he would keep exactly the permissions it defines (Identity read/write on Contoso), just with no `editor` ceiling shaping the result. See Example 4.

### Example 3 — Admin plus a restrictive custom role

Sara is a member of two Entra groups:

* `CIPP-Admins` → mapped to `admin`
* `CIPP-Helpdesk` → the restrictive custom role from Example 2

**Result:** `admin` wins outright and the custom role is **ignored**. Sara has full admin access. To actually limit her, remove the `admin` mapping and give her `editor` (or `readonly`) plus the custom role.

### Example 4 — Custom roles only (no base role)

Priya is a member of one Entra group:

* `CIPP-Reporting` → mapped to a custom role granting **Reports: Read** and **Identity: Read**, Allowed Tenants = `AllTenants`

She is **not** in any group that maps to `editor`, `readonly`, `admin`, or `superadmin`.

**Result:** with no base role, the custom role applies on its own. Priya gets exactly **Reports read** and **Identity read** across all tenants — and nothing else, because every category she was not granted is a deny.

If Priya were also added to a second custom role granting **Endpoint: Read**, her access would be the **union** of the two: Reports read, Identity read, and Endpoint read.

## When CIPP adds new permission categories

CIPP updates occasionally add a permission category, or split an existing one so that a capability can be granted on its own rather than bundled with everything else in its area. The categories listed under **API Permissions** on a custom role are therefore not fixed for the life of an instance.

Existing custom roles are not rewritten when this happens. They keep every permission they already grant, and the capability that moved into the new category becomes a deny, because any category that has not been set is treated as `None`. Users notice this as one part of their access disappearing while the rest of the role carries on working, which tends to be reported as a fault rather than as a permission change.

How much this affects you depends on how the role was built. A role defined in **Simple** mode is a set of patterns, expanded against the current permission list every time it is evaluated, so a wildcard such as `Tenant.*` covers a newly added category in that area without being touched. A role defined in **Advanced** mode grants only the categories it names, as does a pattern written without a wildcard.

After an update, open each custom role on the [cipp-roles](../../user-documentation/cipp/advanced/authentication/cipp-roles/ "mention") page and look through the **API Permissions** list for categories you have not set. Setting a new category to `Read` or `Read/Write` returns the capability to the role, and moving the role to Simple mode with a wildcard pattern avoids meeting the same problem at the next update.

{% hint style="info" %}
Users holding `admin` or `superadmin` are unaffected, as those roles bypass custom roles and receive new permissions automatically.
{% endhint %}

## Testing a role with impersonation

Reasoning about a role on paper is one thing, seeing it is another. Super admins can select **Impersonate Role** against any role on the [cipp-roles](../../user-documentation/cipp/advanced/authentication/cipp-roles/ "mention") page. CIPP reloads and behaves as though they hold that role and nothing else, including its tenant restrictions, and a banner across the top of the page names the role until **Exit impersonation** is selected.

The swap is enforced by the API rather than only by the interface, so anything the role cannot reach fails exactly as it would for a real user holding it. It can only ever narrow access, because the request is honoured only for genuine super admins, and the `superadmin` role itself cannot be impersonated. If the impersonated role cannot load CIPP at all, the banner still appears on the access denied page, so there is always a way back.

{% hint style="warning" %}
Impersonation shows a **single role in isolation**, which is not the same as showing a user. Someone holding a base role alongside one or more custom roles has their access shaped by the combinations described above, so their effective permissions can differ from what impersonation displays. IP restrictions are not simulated.
{% endhint %}

Starting impersonation is written to the logs and attributed to the super admin's real account, not to the role being impersonated.

## Quick reference

| The user holds…​                           | What they get                                                                                               |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| Several built-in roles                     | The single **highest** role.                                                                                |
| `admin` or `superadmin` (+ anything)       | Full built-in access; **custom roles ignored**.                                                             |
| `editor`/`readonly` + one custom role      | Built-in ceiling **filtered down** by the custom role's permissions, tenants, and blocked endpoints.        |
| `editor`/`readonly` + several custom roles | **Union** of the custom roles' grants, still capped by the built-in ceiling; tenant scope checked per role. |
| One custom role, **no** base role          | Exactly what that role explicitly grants — no ceiling. Unset categories are denied.                         |
| Several custom roles, **no** base role     | **Union** of all the roles' explicit grants; tenant scope checked per role.                                 |
| A custom role whose tenant scope resolves to no tenants | **No access to any tenant's data**, whatever permissions the role grants.                       |

{% hint style="info" %}
Because `admin`/`superadmin` bypass custom roles, the most common pattern for scoped access is to map a base role (`editor` or `readonly`) to one Entra group and a custom role to another, then add users to **both** — the base role provides a safe ceiling and the custom role tailors it. Custom-roles-only assignments also work, but without a base-role ceiling they grant exactly what is defined, so review them carefully. See [Custom Roles](../setting-up-cipp/roles.md#custom-roles) for the full setup steps.
{% endhint %}

{% include "../../../.gitbook/includes/feature-request.md" %}

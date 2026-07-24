---
description: How CIPP decides a user's effective permissions when they hold multiple roles
---

# How CIPP Evaluates Roles

CIPP assigns access through **built-in roles** and **custom roles**, and a single user can end up holding several of them at once — especially when roles are mapped to Entra ID groups and a user is a member of more than one group. This page explains, in plain terms, how those roles combine into the permissions a user actually gets.

For instructions on _creating_ roles and mapping them to Entra groups, see [Adding Users and Managing Roles](../self-hosting-guide/roles.md).

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

## Quick reference

| The user holds…​                           | What they get                                                                                               |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------------- |
| Several built-in roles                     | The single **highest** role.                                                                                |
| `admin` or `superadmin` (+ anything)       | Full built-in access; **custom roles ignored**.                                                             |
| `editor`/`readonly` + one custom role      | Built-in ceiling **filtered down** by the custom role's permissions, tenants, and blocked endpoints.        |
| `editor`/`readonly` + several custom roles | **Union** of the custom roles' grants, still capped by the built-in ceiling; tenant scope checked per role. |
| One custom role, **no** base role          | Exactly what that role explicitly grants — no ceiling. Unset categories are denied.                         |
| Several custom roles, **no** base role     | **Union** of all the roles' explicit grants; tenant scope checked per role.                                 |

{% hint style="info" %}
Because `admin`/`superadmin` bypass custom roles, the most common pattern for scoped access is to map a base role (`editor` or `readonly`) to one Entra group and a custom role to another, then add users to **both** — the base role provides a safe ceiling and the custom role tailors it. Custom-roles-only assignments also work, but without a base-role ceiling they grant exactly what is defined, so review them carefully. See [Custom Roles](../self-hosting-guide/roles.md#custom-roles) for the full setup steps.
{% endhint %}

***

{% include "../../../.gitbook/includes/feature-request.md" %}

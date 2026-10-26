# Authentication

Authentication covers who can sign in to CIPP and what they are allowed to do: the CIPP user list, custom CIPP roles and their API permissions, the credentials of the CIPP-SAM and CIPP-SSO app registrations, and the roles and Graph permissions granted to the SAM application.

These pages are limited to users with the `superadmin` role.

{% hint style="danger" %}
As of version 8.0, users only need the \`superadmin\` role in order to access these menus and take actions. The value should be `superadmin` for self-hosted clients. Needing admin in addition to superadmin is no longer valid. Using both you will see errors. CyberDrain hosted clients should select both roles for the user on [https://management.cipp.app/](https://management.cipp.app/)
{% endhint %}

{% hint style="warning" %}
Note that it may take some time for the role change to take effect.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}

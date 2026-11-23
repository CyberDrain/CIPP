---
description: Limit which IP addresses can reach a CyberDrain-hosted CIPP instance
---

# Restricting Access by IP Address

CyberDrain-hosted clients can limit their CIPP instance to a list of trusted IP addresses from the [management portal](https://management.cipp.app/). Once a list is saved, anyone connecting from an address that is not on it gets a 403 error instead of the CIPP sign-in page, even with valid credentials. This adds a network check on top of SSO and Conditional Access, rather than replacing them.

IP restrictions are available for instances on the new CIPP infrastructure. If your instance has not been migrated yet, the page shows **Not available for this instance**. See [migrating-to-the-latest-version-of-cipp.md](../maintaining-cipp/migrating-to-the-latest-version-of-cipp.md "mention").

{% hint style="warning" %}
The list applies to everyone. Staff working from home or travelling, and CyberDrain support, are blocked unless their address is listed. The restriction also covers the [CIPP API and MCP server](../../user-documentation/cipp/integrations/cipp-api.md): a PSA, automation platform, or AI client that connects to either needs its outbound addresses on the list.
{% endhint %}

## Before You Start

* Collect the public IPv4 addresses your team connects from: office connections, VPN exit points, and any integration or AI client that connects to the CIPP API or MCP server.
* Only IPv4 is supported. Enter a single address (`203.0.113.10`) or a range in CIDR notation (`198.51.100.0/28`).
* The list holds up to 100 entries. A `/0` range is refused, because it would allow every address.

The management portal itself is never restricted, so you can always return to it to change or remove the list if you lock yourself out of CIPP.

## Setting Up IP Restrictions

{% stepper %}
{% step %}
### Open IP Restrictions

Sign in to the [management portal](https://management.cipp.app/) and select **IP Restrictions** from the menu.

The banner at the top shows the current state: **Your CIPP instance is reachable from any address** when nothing is restricted, or **Your CIPP instance is restricted to the addresses below** once a list is in place.
{% endstep %}

{% step %}
### Add your addresses

Type each address or range into **Allowed IPs (CIDR)** and press Enter. You can paste several at once, separated by commas, semicolons, or spaces.

**Your current address** shows the address the portal sees you connecting from. Select **Add my IP** to add it to the list as a single address. The button is unavailable when your current address is not IPv4.
{% endstep %}

{% step %}
### Save the list

Select **Save**. The change applies straight away, and the confirmation tells you how many address ranges are now allowed.

If your current address is not covered by the list, the save stops with a warning that you will lose access to CIPP from where you are now. To go ahead anyway, tick **I understand I may lose access from my current address** and select **Save** again. The confirmation covers that one save only; changing the list asks again.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
If the page warns that your instance has other access rules not shown in the list, those were set up separately, for example by CyberDrain support. Saving replaces them with your list. Contact helpdesk@cyberdrain.com first if you are not sure what they are for.
{% endhint %}

CyberDrain's monitoring of your instance stays allowed automatically, so you do not need to add it.

## Changing or Removing Restrictions

To change the list, add or remove entries in **Allowed IPs (CIDR)** and select **Save**.

To open your instance to every address again, select **Remove all restrictions** and confirm. CIPP is reachable from anywhere as soon as the change is saved.

## Troubleshooting

| Symptom | Cause | What to do |
| --- | --- | --- |
| You or a colleague get a 403 error opening CIPP | The address you are connecting from is not on the list. | Sign in to the management portal, select **Add my IP** or enter the address, and save. |
| An integration or AI client using the CIPP API or MCP server has stopped working | Its outbound addresses are not on the list. | Ask the vendor for its outbound IP addresses and add them. |
| A save fails with **Invalid IP entry** | An entry is not a valid IPv4 address or range, or uses a `/0` range. | Correct the entry named in the message and save again. |
| **Add my IP** is unavailable | You are connecting over IPv6, which the list does not support. | Connect over IPv4, or enter your network's public IPv4 address by hand. |

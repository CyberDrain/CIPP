# Remote Networks

Lists the Global Secure Access remote networks (branch sites) in the selected tenant, read live from the tenant. Open it from the **Remote networks** tab on the Traffic Forwarding page. To change which profiles a site uses, edit the profile on the [Traffic Forwarding](README.md) page.

## Table Details

| Column       | Description                                                                                                  |
| ------------ | ------------------------------------------------------------------------------------------------------------ |
| Name         | The remote network name.                                                                                     |
| Region       | The Microsoft region the site connects to.                                                                   |
| Profiles     | The traffic forwarding profiles the site uses.                                                               |
| Device Links | The site's devices: name, public IP address, vendor, bandwidth and BGP ASN. Empty if they could not be read. |

The VPN pre-shared key of a device link is never shown or stored by CIPP.

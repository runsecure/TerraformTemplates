# windows-2025-core-iis-base (Vultr)

A tightly locked down Windows Server 2025 base template on Vultr, with IIS
and .NET Framework 4.5/ASP.NET pre-installed, intended as the starting
point for further configuration via Ansible. This follows the same
security intent as the Azure/AWS/GCP counterparts in this repo, adapted to
a much simpler provider surface.

## Verify before use

Vultr's Terraform provider (`vultr/vultr`) and OS catalog are less stable
in this author's working knowledge than the hyperscaler providers used
elsewhere in this repo. **Before applying, cross-check every resource and
attribute name in `main.tf`/`variables.tf` against the current
[Terraform Registry docs for `vultr/vultr`](https://registry.terraform.io/providers/vultr/vultr/latest/docs)**,
and confirm the OS catalog entry with:

```sh
vultr-cli os list | grep -i windows
```

Two specific things this template cannot verify without live API access:

- **Whether Vultr publishes a Windows Server 2025 image at all yet**, and
  under what exact catalog name (`os_name_filter` defaults to
  `"Windows 2025 x64"`, following the `"Windows <year> x64"` pattern seen
  in past Vultr catalogs).
- **Whether Vultr offers a Server Core (no GUI) variant.** If not, the
  closest full Desktop Experience image still works with this template -
  Core vs. Desktop doesn't change the IIS/SSH configuration below, you'll
  just have a GUI you didn't strictly need (and RDP is still closed at
  both the firewall group and host firewall regardless).

## The big architectural difference from the other templates

**Vultr instances always get a public IPv4 address.** There is no
VPC/NSG-style "private subnet, no public IP" option the way there is on
Azure/AWS/GCP - Vultr's whole model is simpler and assumes a public
interface. That means the *only* network-layer boundary here is the
`vultr_firewall_group` - there's no way to make this instance
unreachable-by-design the way the hyperscaler templates default to. Keep
`admin_source_cidr_blocks` tight.

## Security posture

- **No RDP, no WinRM.** The only inbound management path is SSH (TCP/22),
  provided by the Windows OpenSSH Server capability. RDP is disabled at
  the host firewall and never opened in the firewall group. WinRM's
  service and listeners are removed.
- **Key-only SSH.** `PasswordAuthentication` is disabled in `sshd_config`;
  only the public key supplied via `ssh_public_key` can log in, via
  `administrators_authorized_keys` (locked down to `SYSTEM`/`Administrators`
  only, as OpenSSH requires).
- **No open access by default.** `admin_source_cidr_blocks` has no default
  and must be set explicitly.
- **Firewall group** allows only SSH (from the admin allow-list) and
  HTTP/HTTPS (from `web_source_cidr_blocks`, defaulting to the internet,
  since this is a web server).
- **Host firewall** mirrors the firewall group: default-deny inbound,
  explicit allows for 22/80/443 only.
- **Protocol hardening:** SMBv1 is disabled; SSLv2/v3 and TLS 1.0/1.1 are
  disabled via SCHANNEL registry settings, TLS 1.2 is enforced.
- IPv6 is disabled by default (`enable_ipv6 = false`) to keep the exposed
  surface to a single stack that the firewall group actually covers.

## What gets installed

Via `Install-WindowsFeature` (see `scripts/bootstrap.ps1.tftpl`, delivered
as `user_data` and executed by Cloudbase-Init - Vultr/Windows's equivalent
of cloud-init - because the script is prefixed with the `#ps1_sysnative`
marker Cloudbase-Init looks for):

- `Web-Server` and core IIS sub-features (static content, default doc,
  HTTP errors/logging, request filtering, compression, ISAPI ext/filter,
  management console)
- `NET-Framework-45-Core`, `NET-Framework-45-ASPNET`, `Web-Asp-Net45`,
  `Web-Net-Ext45`

## Usage

```hcl
module "web01" {
  source = "./vultr/windows-2025-core-iis-base"

  name_prefix = "web01"
  region      = "ewr"

  admin_source_cidr_blocks = ["203.0.113.10/32"] # your Ansible control node
  ssh_public_key           = file("~/.ssh/ansible_ed25519.pub")
}
```

Or `cd` into this directory, export `VULTR_API_KEY`, copy
`terraform.tfvars.example` to `terraform.tfvars`, fill it in, and run it as
a root module:

```sh
export VULTR_API_KEY="..."
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

After apply, add the host to your Ansible inventory using the
`public_ip_address` and `admin_username` outputs, with
`ansible_connection: ssh` and `ansible_shell_type: powershell`.

## Inputs / outputs

See `variables.tf` and `outputs.tf` for the full list.

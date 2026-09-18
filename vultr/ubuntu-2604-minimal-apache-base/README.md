# ubuntu-2604-minimal-apache-base (Vultr)

A tightly locked down Ubuntu 26.04 LTS server on Vultr, with Apache
pre-installed, intended as the starting point for further configuration
via Ansible over SSH. This follows the same security intent as the
Azure/AWS/GCP counterparts in this repo, adapted to a much simpler
provider surface.

## Verify before use

Vultr's Terraform provider (`vultr/vultr`) and OS catalog are less stable
in this author's working knowledge than the hyperscaler providers used
elsewhere in this repo. **Before applying, cross-check every resource and
attribute name in `main.tf`/`variables.tf` against the current
[Terraform Registry docs for `vultr/vultr`](https://registry.terraform.io/providers/vultr/vultr/latest/docs)**,
and confirm the OS catalog entry with:

```sh
vultr-cli os list | grep -i ubuntu
```

`os_name_filter` defaults to `"Ubuntu 26.04 LTS x64"`; if 26.04 isn't
published yet, override it to `"Ubuntu 24.04 LTS x64"`.

Note also that this template does not use Vultr's native `ssh_key_ids`
mechanism, since that applies to the image's default account (often
`root`) rather than a dedicated non-root user. Instead, the SSH key and
`admin_username` account are both created via cloud-init `user_data` -
verify your chosen Ubuntu image on Vultr actually runs cloud-init on
first boot (the standard Vultr Ubuntu OS entries do).

## The big architectural difference from the other templates

**Vultr instances always get a public IPv4 address.** There is no
VPC/NSG-style "private subnet, no public IP" option the way there is on
Azure/AWS/GCP. The *only* network-layer boundary here is the
`vultr_firewall_group`. Keep `admin_source_cidr_blocks` tight.

## Security posture

- **Key-only SSH.** cloud-init creates `admin_username` with
  `lock_passwd: true` and only the supplied `ssh_public_key`, then
  additionally hardens `sshd_config` (`PermitRootLogin no`,
  `PasswordAuthentication no`, `KbdInteractiveAuthentication no`) and
  restarts `ssh`.
- **No open access by default.** `admin_source_cidr_blocks` has no default
  and must be set explicitly.
- **Firewall group** allows only SSH (from the admin allow-list) and
  HTTP/HTTPS (from `web_source_cidr_blocks`, defaulting to the internet,
  since this is a web server).
- **Host firewall (ufw)** mirrors the firewall group: default-deny
  inbound, default allow outbound, explicit allows for 22/80/443 only.
- **fail2ban** (on by default) mitigates SSH brute-force attempts.
- **unattended-upgrades** (on by default) applies security patches
  automatically.
- IPv6 is disabled by default (`enable_ipv6 = false`) to keep the exposed
  surface to a single stack that the firewall group actually covers.
- Apache is minimally configured: `ServerTokens Prod`, `ServerSignature Off`,
  `TraceEnable Off` to avoid leaking version/banner information.

## Sizing and storage

- **`plan`** bundles vCPU, memory, *and* the boot disk size together -
  Vultr has no independent knobs for any of these. Pick a plan matching
  what you need via `vultr-cli plans list`.
- **`data_disks`** attaches additional Vultr Block Storage volumes beyond
  the plan's included disk (each `{ size_gb }`). cloud-init formats each
  one ext4 and mounts it under `/mnt/dataN` automatically. See the
  `data_disk_ids` output. **Verify the `vultr_block_storage` resource's
  exact schema** (particularly `attached_to_instance`) against the
  current provider docs - see "Verify before use" above.
- **`additional_mounts`** mounts *existing* network storage inside the
  instance at boot - an NFS export, an SMB/CIFS share, or an S3 bucket
  (via `s3fs`). This does not provision the storage itself. Example:
  ```hcl
  additional_mounts = [
    { type = "nfs", source = "203.0.113.5:/export", mount_point = "/mnt/shared" },
  ]
  ```

## Usage

```hcl
module "web01" {
  source = "./vultr/ubuntu-2604-minimal-apache-base"

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
`ansible_connection: ssh`.

## Inputs / outputs

See `variables.tf` and `outputs.tf` for the full list.

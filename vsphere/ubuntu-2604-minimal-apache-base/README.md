# ubuntu-2604-minimal-apache-base (VMware vSphere / on-prem)

A tightly locked down Ubuntu 26.04 LTS server on VMware vSphere, with
Apache pre-installed, intended as the starting point for further
configuration via Ansible over SSH. This follows the same host-level
security intent as the Azure/AWS/GCP/Vultr counterparts in this repo, but
the on-prem model is fundamentally different from all of them - read this
whole README before using it.

## How this is fundamentally different from the cloud templates

- **No marketplace image lookup.** `template_name` must already exist in
  vCenter as an Ubuntu 26.04 minimal VM with **cloud-init >= 21.3
  installed and its VMware guestinfo datasource available** (Canonical's
  official Ubuntu OVA cloud images ship this already), then had
  **`cloud-init clean` run before being shut down and converted to a
  template**. Skip that step and cloud-init won't recognize the clone as
  a new instance, and none of the provisioning below will run.
- **No Terraform-managed network security boundary.** Segmentation
  (VLANs, NSX-T distributed firewall rules, a physical firewall) is your
  infrastructure team's job here, outside Terraform's vsphere provider
  entirely. **The `ufw` rules configured by cloud-init are the primary
  control, not defense-in-depth.**
- **No native vSphere guest customization is used** (unlike the Windows
  counterpart's `clone.customize.windows_options`) - Linux customization
  goes through cloud-init reading two VMware `extra_config` guestinfo
  keys instead: `guestinfo.userdata` (the cloud-config below) and
  `guestinfo.metadata` (a per-clone `instance-id`/`local-hostname`, so
  each clone is recognized as distinct). This is the current recommended
  pattern for cloud-init-enabled Linux templates on vSphere.
- **IP addressing** defaults to DHCP (whatever the template's netplan
  already does). Setting `ipv4_address` renders a cloud-init
  network-config v2 file via a third guestinfo key
  (`guestinfo.network-config`) - **verify `network_interface_name`
  (default `ens192`) actually matches your template's interface** with
  `ip -br link` before relying on this; if it's wrong, the static config
  silently won't apply to any real interface.

## Security posture (host-level)

- **Key-only SSH.** cloud-init creates `admin_username` with
  `lock_passwd: true` and only the supplied `ssh_public_key`, then
  additionally hardens `sshd_config` (`PermitRootLogin no`,
  `PasswordAuthentication no`, `KbdInteractiveAuthentication no`) and
  restarts `ssh`.
- **Host firewall (ufw)**: default-deny inbound, default allow outbound,
  explicit allows for 22/80/443 only.
- **fail2ban** (on by default) mitigates SSH brute-force attempts.
- **unattended-upgrades** (on by default) applies security patches
  automatically.
- Apache is minimally configured: `ServerTokens Prod`, `ServerSignature Off`,
  `TraceEnable Off` to avoid leaking version/banner information.

## Usage

```hcl
module "web01" {
  source = "./vsphere/ubuntu-2604-minimal-apache-base"

  datacenter    = "DC01"
  cluster       = "Cluster01"
  datastore     = "datastore1"
  network       = "VM Network"
  template_name = "ubuntu-2604-minimal-golden"

  name_prefix    = "web01"
  ssh_public_key = file("~/.ssh/ansible_ed25519.pub")
}
```

Or `cd` into this directory, export vCenter credentials, copy
`terraform.tfvars.example` to `terraform.tfvars`, fill it in, and run it as
a root module:

```sh
export VSPHERE_SERVER="vcenter.lab.example.com"
export VSPHERE_USER="administrator@vsphere.local"
export VSPHERE_PASSWORD="..."
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

After apply, add the host to your Ansible inventory using the
`ip_address` and `admin_username` outputs, with `ansible_connection: ssh`.

## Before you apply

- **Confirm the template was prepared correctly**: cloud-init installed
  and enabled, `cloud-init clean --logs` run, then shut down (not just
  powered off) before converting to a template. This is the single most
  common failure point for this pattern.
- **Verify `network_interface_name`** against your actual template if
  using a static IP.

## Inputs / outputs

See `variables.tf` and `outputs.tf` for the full list.

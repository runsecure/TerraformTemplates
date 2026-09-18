# windows-2025-core-iis-base (VMware vSphere / on-prem)

A tightly locked down Windows Server 2025 Core base template on VMware
vSphere, with IIS and .NET Framework 4.5/ASP.NET pre-installed, intended
as the starting point for further configuration via Ansible. This follows
the same host-level security intent as the Azure/AWS/GCP/Vultr
counterparts in this repo, but the on-prem model is fundamentally
different from all of them - read this whole README before using it.

## How this is fundamentally different from the cloud templates

- **No marketplace image lookup.** There is no `data "aws_ami"` /
  `google_compute_image` equivalent here. `template_name` must already
  exist in vCenter as a Windows Server 2025 Core VM that has been
  **sysprepped and shut down** (VMware Tools installed, sysprep files
  present) - you build this golden image yourself, outside this template,
  and keep it patched.
- **No Terraform-managed network security boundary.** Azure/AWS/GCP
  templates in this repo provision their own NSG/security
  group/firewall rules as the primary control. On vSphere, `network`
  just picks a port group/VLAN - actual segmentation (VLANs, NSX-T
  distributed firewall rules, a physical firewall) is your infrastructure
  team's job, outside Terraform's vsphere provider entirely. **The
  Windows host firewall configured by the bootstrap script is the primary
  control here, not defense-in-depth.**
- **Post-clone bootstrapping uses sysprep's `run_once_command_list`**
  (VMware guest customization), not cloud-init/user-data. The full
  bootstrap script is base64/UTF-16LE-encoded into a single
  `powershell.exe -EncodedCommand ...` RunOnce entry - the same trick used
  in the Azure template, needed here because sysprep's RunOnce mechanism
  has no separate "upload a script file" concept. This has a real (generous,
  ~32KB) command-line length ceiling - if you grow the script substantially,
  consider baking more into the golden template instead.
- **IP addressing** defaults to DHCP; set `ipv4_address` /
  `ipv4_prefix_length` / `ipv4_gateway` / `dns_server_list` for a static
  assignment (common on-prem, since DHCP reservations/IPAM are often
  managed outside Terraform here).

## Security posture (host-level)

- **No RDP, no WinRM.** The only inbound management path is SSH (TCP/22),
  provided by the Windows OpenSSH Server capability. RDP is disabled at
  the host firewall. WinRM's service and listeners are removed.
- **Key-only SSH.** `PasswordAuthentication` is disabled in `sshd_config`;
  only the public key supplied via `ssh_public_key` can log in, via
  `administrators_authorized_keys` (locked down to `SYSTEM`/`Administrators`
  only, as OpenSSH requires).
- **Host firewall**: default-deny inbound, explicit allows for 22/80/443
  only.
- **Protocol hardening:** SMBv1 is disabled; SSLv2/v3 and TLS 1.0/1.1 are
  disabled via SCHANNEL registry settings, TLS 1.2 is enforced.
- The local administrator password is set via vSphere guest customization
  (sysprep), not by the bootstrap script - Terraform generates one if you
  don't supply `admin_password`.

## Sizing and storage

Unlike the cloud templates, vSphere lets you dial vCPU, memory, and disk
size independently - there's no fixed SKU catalog:

- **`num_cpus`** / **`memory_mb`** set vCPU and memory directly.
- **`disk_size_gb`** sizes the primary disk (null inherits the template's
  own size).
- **`data_disks`** attaches additional virtual disks on the same
  datastore beyond the primary disk (each `{ size_gb }`), as native
  vSphere disk devices. The bootstrap script brings each one online,
  initializes it GPT, and formats it NTFS automatically.
- **`additional_mounts`** mounts *existing* network storage inside the VM
  at boot - an NFS export or an SMB/CIFS share reachable on your network.
  This does not provision the storage itself. S3 has no native Windows
  mount path, so `type = "s3"` entries are skipped with a warning.
  Example:
  ```hcl
  additional_mounts = [
    { type = "smb", source = "\\\\fileserver\\share", mount_point = "Z:" },
  ]
  ```

## What gets installed

Via `Install-WindowsFeature` (see `scripts/bootstrap.ps1.tftpl`, delivered
via sysprep's `run_once_command_list`):

- `Web-Server` and core IIS sub-features (static content, default doc,
  HTTP errors/logging, request filtering, compression, ISAPI ext/filter,
  management console)
- `NET-Framework-45-Core`, `NET-Framework-45-ASPNET`, `Web-Asp-Net45`,
  `Web-Net-Ext45`

Note: `Add-WindowsCapability -Online` (for OpenSSH Server) needs outbound
internet access, a WSUS, or a local FOD source - if your golden template
lives on an air-gapped/restricted network, bake OpenSSH Server into the
template itself instead of relying on this script to fetch it.

## Usage

```hcl
module "web01" {
  source = "./vsphere/windows-2025-core-iis-base"

  datacenter    = "DC01"
  cluster       = "Cluster01"
  datastore     = "datastore1"
  network       = "VM Network"
  template_name = "win2025-core-golden"

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
`ip_address` and `admin_username` outputs, with `ansible_connection: ssh`
and `ansible_shell_type: powershell`.

## Before you apply

- **Verify `windows_time_zone`.** This uses VMware's legacy numeric
  Microsoft time zone index (not the modern IANA/Windows time zone name).
  The default (35) is documented in various references as Pacific
  Standard Time - cross-check against Microsoft's historical time zone
  index table for your target zone.
- **Confirm the template is actually sysprepped and shut down**, not just
  powered off mid-run - vSphere guest customization silently produces a
  broken clone otherwise.
- **Protect Terraform state.** If `admin_password` is left unset, a random
  password is generated and stored in state as the sensitive
  `admin_password` output. Use a remote backend with encryption and
  restricted access.

## Inputs / outputs

See `variables.tf` and `outputs.tf` for the full list.

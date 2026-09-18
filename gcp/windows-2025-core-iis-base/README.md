# windows-2025-core-iis-base (GCP)

A tightly locked down Windows Server 2025 Core (no desktop experience) base
template on Google Cloud, with IIS and .NET Framework 4.5/ASP.NET
pre-installed, intended as the starting point for further configuration via
Ansible. This follows the same security model as the Azure and AWS
counterparts in this repo.

## Security posture

- **No RDP, no WinRM.** The only inbound management path is SSH (TCP/22),
  provided by the Windows OpenSSH Server capability. RDP is disabled at the
  host firewall and never opened at the network layer. WinRM's service and
  listeners are removed.
- **Key-only SSH.** `PasswordAuthentication` is disabled in `sshd_config`;
  only the public key supplied via `ssh_public_key` can log in, via
  `administrators_authorized_keys` (locked down to `SYSTEM`/`Administrators`
  only, as OpenSSH requires).
- **No open access by default.** `admin_source_cidr_ranges` has no default
  and must be set explicitly - point it at your Ansible control node(s) or
  management VPN/Cloud Interconnect range. There is no external IP unless
  `enable_public_ip = true`.
- **Custom-mode VPC** with no default-allow rules: only what's explicitly
  opened here (SSH from the admin allow-list, HTTP/HTTPS from
  `web_source_cidr_ranges`) is reachable, gated by a firewall target tag
  applied only to this instance.
- **Host firewall** mirrors the network layer: default-deny inbound,
  explicit allows for 22/80/443 only.
- **Protocol hardening:** SMBv1 is disabled; SSLv2/v3 and TLS 1.0/1.1 are
  disabled via SCHANNEL registry settings, TLS 1.2 is enforced (including
  for .NET Framework's `SchUseStrongCrypto`/`SystemDefaultTlsVersions`).
- **Shielded VM** (Secure Boot + vTPM + integrity monitoring) is enabled by
  default - GCP's equivalent of Trusted Launch.
- **No service account is attached** to the instance, so it has no GCP API
  access by default (add a scoped `service_account` block if the
  application needs one later).
- Boot disks are encrypted at rest by Google by default; no extra
  configuration needed.

Everything above is infrastructure/host-layer lockdown. Application-level
IIS site configuration, TLS certificates, and further OS hardening are
expected to be layered on afterwards via Ansible over the SSH connection
this template sets up.

## Networking and internet egress

GCP instances without an external IP still get outbound internet access by
default via Private Google Access / Cloud NAT-free default routing for
some destinations, but general internet egress for a private instance
technically requires Cloud NAT in production VPCs. This template does not
provision Cloud NAT. If `enable_public_ip = false` and your project/VPC
doesn't otherwise provide egress, the bootstrap script's
`Add-WindowsCapability` call (installing OpenSSH Server) may fail without
outbound internet access - add Cloud NAT, or set `enable_public_ip = true`,
if you hit this.

## Sizing and storage

- **`machine_type`** controls vCPU and memory together via a predefined
  catalog SKU. GCP also lets you dial them independently with a **custom
  machine type**: set both `custom_cpu_count` and `custom_memory_mb` to
  build `custom-<cpus>-<memory_mb>` (this overrides `machine_type`
  entirely). Memory must be a multiple of 256 MB; most families need an
  even vCPU count >= 2.
- **`boot_disk_size_gb`** / **`boot_disk_type`** control the boot disk.
- **`data_disks`** attaches additional empty persistent disks beyond the
  boot disk (each `{ size_gb, type }`). The bootstrap script brings each
  one online, initializes it GPT, and formats it NTFS automatically. See
  the `data_disk_ids` output.
- **`additional_mounts`** mounts *existing* network storage inside the
  instance at boot - an NFS export (Filestore, etc.) or an SMB/CIFS share
  (a generic NAS). This does not provision the storage itself. S3 has no
  native Windows mount path, so `type = "s3"` entries are skipped with a
  warning. Example:
  ```hcl
  additional_mounts = [
    { type = "nfs", source = "10.0.0.4:/vol1", mount_point = "Z:" },
  ]
  ```

## What gets installed

Via `Install-WindowsFeature` (see `scripts/bootstrap.ps1.tftpl`, delivered
via the `windows-startup-script-ps1` metadata key and run by the GCE
Windows guest agent on first boot):

- `Web-Server` and core IIS sub-features (static content, default doc,
  HTTP errors/logging, request filtering, compression, ISAPI ext/filter,
  management console)
- `NET-Framework-45-Core`, `NET-Framework-45-ASPNET`, `Web-Asp-Net45`,
  `Web-Net-Ext45`

## Usage

```hcl
module "web01" {
  source = "./gcp/windows-2025-core-iis-base"

  project_id  = "my-gcp-project"
  name_prefix = "web01"

  admin_source_cidr_ranges = ["203.0.113.10/32"] # your Ansible control node
  ssh_public_key           = file("~/.ssh/ansible_ed25519.pub")
}
```

Or `cd` into this directory, copy `terraform.tfvars.example` to
`terraform.tfvars`, fill it in, and run it as a root module:

```sh
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

After apply, add the host to your Ansible inventory using the
`private_ip_address` (or `public_ip_address` if `enable_public_ip = true`)
and `admin_username` outputs, with `ansible_connection: ssh` and
`ansible_shell_type: powershell`.

## Before you apply

- **Verify `image_family`** for your project's image access:
  ```sh
  gcloud compute images list --project windows-cloud --filter="family~2025" --format="table(name,family)"
  ```
- **Protect Terraform state.** If `admin_password` is left unset, a random
  password is generated and stored in state as the sensitive
  `admin_password` output (needed as a break-glass credential; day-to-day
  access is via SSH key). Use a remote backend (e.g. GCS with CMEK) with
  restricted access.

## Inputs / outputs

See `variables.tf` and `outputs.tf` for the full list.

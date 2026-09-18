# windows-2025-core-iis-base

A tightly locked down Windows Server 2025 Core (no desktop experience) base
template on Azure, with IIS and .NET Framework 4.5/ASP.NET pre-installed,
intended as the starting point for further configuration via Ansible.

## Security posture

- **No RDP, no WinRM.** The only inbound management path is SSH (TCP/22),
  provided by the Windows OpenSSH Server capability. RDP is disabled at the
  host firewall and never opened in the NSG. WinRM's service and listeners
  are removed.
- **Key-only SSH.** `PasswordAuthentication` is disabled in `sshd_config`;
  only the public key supplied via `ssh_public_key` can log in, via
  `administrators_authorized_keys` (locked down to `SYSTEM`/`Administrators`
  only, as OpenSSH requires).
- **No open access by default.** `admin_source_address_prefixes` has no
  default and must be set explicitly - point it at your Ansible control
  node(s) or management VPN/jump host range. There is no public IP unless
  `enable_public_ip = true`.
- **Network Security Group** allows only SSH (from the admin allow-list) and
  HTTP/HTTPS (from `web_source_address_prefixes`, defaulting to the
  internet, since this is a web server). An explicit deny-all inbound rule
  backs up the platform's implicit default deny.
- **Host firewall** mirrors the NSG: default-deny inbound, explicit allows
  for 22/80/443 only.
- **Protocol hardening:** SMBv1 is disabled; SSLv2/v3 and TLS 1.0/1.1 are
  disabled via SCHANNEL registry settings, TLS 1.2 is enforced (including
  for .NET Framework's `SchUseStrongCrypto`/`SystemDefaultTlsVersions`).
- **Trusted Launch** (Secure Boot + vTPM) is enabled by default (requires
  the Gen2 image, which is the default `image_sku`).
- Automatic platform-managed patching (`patch_mode = "AutomaticByPlatform"`).

Everything above is infrastructure/host-layer lockdown. Application-level
IIS site configuration, TLS certificates, and further OS hardening are
expected to be layered on afterwards via Ansible over the SSH connection
this template sets up.

## What gets installed

Via `Install-WindowsFeature` (see `scripts/bootstrap.ps1.tftpl`):

- `Web-Server` and core IIS sub-features (static content, default doc,
  HTTP errors/logging, request filtering, compression, ISAPI ext/filter,
  management console)
- `NET-Framework-45-Core`, `NET-Framework-45-ASPNET`, `Web-Asp-Net45`,
  `Web-Net-Ext45`

## Usage

```hcl
module "web01" {
  source = "./azure/windows-2025-core-iis-base"

  name_prefix = "web01"
  location    = "eastus"

  admin_source_address_prefixes = ["203.0.113.10/32"] # your Ansible control node
  ssh_public_key                = file("~/.ssh/ansible_ed25519.pub")
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

- **Verify `image_sku`** for your target region - Windows Server 2025
  marketplace SKU strings can vary by region/rollout:
  ```sh
  az vm image list-skus --location <region> \
    --publisher MicrosoftWindowsServer --offer WindowsServer -o table
  ```
- **Protect Terraform state.** If `admin_password` is left unset, a random
  password is generated and stored in state as the sensitive
  `admin_password` output (needed as a break-glass/VM Agent credential;
  day-to-day access is via SSH key). Use a remote backend with encryption
  and restricted access.
- `enable_encryption_at_host` defaults to `false` because it requires the
  `Microsoft.Compute/EncryptionAtHost` feature to be registered on the
  subscription first; enable it once that's done.

## Inputs / outputs

See `variables.tf` and `outputs.tf` for the full list.

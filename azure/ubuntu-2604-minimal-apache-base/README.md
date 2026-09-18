# ubuntu-2604-minimal-apache-base

A tightly locked down Ubuntu 26.04 LTS minimal server on Azure, with Apache
pre-installed, intended as the starting point for further configuration via
Ansible over SSH.

## Security posture

- **Key-only SSH.** The VM is created with `disable_password_authentication = true`
  and an `admin_ssh_key` block - no password login exists from first boot.
  Cloud-init additionally hardens `sshd_config` (`PermitRootLogin no`,
  `PasswordAuthentication no`, `KbdInteractiveAuthentication no`) and restarts
  `ssh` to apply it.
- **No open access by default.** `admin_source_address_prefixes` has no
  default and must be set explicitly - point it at your Ansible control
  node(s) or management VPN/jump host range. There is no public IP unless
  `enable_public_ip = true`.
- **Network Security Group** allows only SSH (from the admin allow-list) and
  HTTP/HTTPS (from `web_source_address_prefixes`, defaulting to the
  internet, since this is a web server). An explicit deny-all inbound rule
  backs up the platform's implicit default deny.
- **Host firewall (ufw)** mirrors the NSG: default-deny inbound, default
  allow outbound, explicit allows for 22/80/443 only.
- **fail2ban** (on by default) mitigates SSH brute-force attempts.
- **unattended-upgrades** (on by default) applies security patches
  automatically; `patch_mode = "AutomaticByPlatform"` also enables Azure's
  platform-managed guest patching.
- **Trusted Launch** (Secure Boot + vTPM) is enabled by default (requires
  the Gen2 image, which is the default for the `minimal` SKU).
- Apache is minimally configured: `ServerTokens Prod`, `ServerSignature Off`,
  `TraceEnable Off` to avoid leaking version/banner information.

Everything above is infrastructure/host-layer lockdown. Site configuration,
TLS certificates, and further OS hardening are expected to be layered on
afterwards via Ansible over the SSH connection this template sets up.

## Usage

```hcl
module "web01" {
  source = "./azure/ubuntu-2604-minimal-apache-base"

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
and `admin_username` outputs, with `ansible_connection: ssh`.

## Before you apply

- **Verify `image_offer`/`image_sku`** for your target region - Canonical's
  marketplace strings can shift as new releases roll out:
  ```sh
  az vm image list-skus --location <region> \
    --publisher Canonical --offer ubuntu-26_04-lts -o table
  ```
  If `ubuntu-26_04-lts` isn't published yet in your region/subscription at
  apply time, fall back to the prior LTS (`ubuntu-24_04-lts`) via
  `image_offer` until it is.
- `enable_encryption_at_host` defaults to `false` because it requires the
  `Microsoft.Compute/EncryptionAtHost` feature to be registered on the
  subscription first; enable it once that's done.

## Inputs / outputs

See `variables.tf` and `outputs.tf` for the full list.

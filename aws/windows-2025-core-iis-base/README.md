# windows-2025-core-iis-base (AWS)

A tightly locked down Windows Server 2025 Core (no desktop experience) base
template on AWS, with IIS and .NET Framework 4.5/ASP.NET pre-installed,
intended as the starting point for further configuration via Ansible. This
is the AWS counterpart to `../../azure/windows-2025-core-iis-base` and
follows the same security model.

## Security posture

- **No RDP, no WinRM.** The only inbound management path is SSH (TCP/22),
  provided by the Windows OpenSSH Server capability. RDP is disabled at the
  host firewall and never opened in the security group. WinRM's service and
  listeners are removed.
- **Key-only SSH.** `PasswordAuthentication` is disabled in `sshd_config`;
  only the public key supplied via `ssh_public_key` can log in, via
  `administrators_authorized_keys` (locked down to `SYSTEM`/`Administrators`
  only, as OpenSSH requires).
- **No open access by default.** `admin_source_cidr_blocks` has no default
  and must be set explicitly - point it at your Ansible control node(s) or
  management VPN/jump host range. There is no Elastic IP unless
  `enable_public_ip = true`.
- **Security group** allows only SSH (from the admin allow-list) and
  HTTP/HTTPS (from `web_source_cidr_blocks`, defaulting to the internet,
  since this is a web server, but only reachable once a public IP exists).
- **Host firewall** mirrors the security group: default-deny inbound,
  explicit allows for 22/80/443 only.
- **Protocol hardening:** SMBv1 is disabled; SSLv2/v3 and TLS 1.0/1.1 are
  disabled via SCHANNEL registry settings, TLS 1.2 is enforced (including
  for .NET Framework's `SchUseStrongCrypto`/`SystemDefaultTlsVersions`).
- **EBS root volume is encrypted** and **IMDSv2 is enforced**
  (`http_tokens = "required"`).

Everything above is infrastructure/host-layer lockdown. Application-level
IIS site configuration, TLS certificates, and further OS hardening are
expected to be layered on afterwards via Ansible over the SSH connection
this template sets up.

## Networking and internet egress - read this before applying

Unlike Azure, AWS instances without a public/Elastic IP have **no outbound
internet access at all** unless something provides it (NAT gateway,
existing VPC egress, etc). The bootstrap script's `Add-WindowsCapability`
call (installing OpenSSH Server) needs internet access to Windows Update
the first time it runs, so this template provisions its own NAT gateway by
default (`enable_nat_gateway = true`) when `enable_public_ip = false`, so
the instance stays unreachable from the internet while still being able to
provision itself correctly.

**This has a real cost** (NAT gateway hourly charge + per-GB data
processing). Options:

- Keep the default: private instance, NAT gateway pays for egress. Most
  faithful to "tightly locked down."
- `enable_public_ip = true`: instance gets a static Elastic IP and a direct
  route to an internet gateway (cheaper than NAT, but the instance is then
  reachable on 80/443 from `web_source_cidr_blocks`, which is expected for
  a web server).
- `enable_nat_gateway = false` with `enable_public_ip = false`: no internet
  egress at all. Only use this if your VPC already provides egress some
  other way (peering, Transit Gateway, VPN to on-prem with a proxy, etc.),
  otherwise the OpenSSH capability install (and any Windows Update–backed
  step) will fail.

## What gets installed

Via `Install-WindowsFeature` (see `scripts/bootstrap.ps1.tftpl`, delivered
as EC2 user-data and run by EC2Launch on first boot):

- `Web-Server` and core IIS sub-features (static content, default doc,
  HTTP errors/logging, request filtering, compression, ISAPI ext/filter,
  management console)
- `NET-Framework-45-Core`, `NET-Framework-45-ASPNET`, `Web-Asp-Net45`,
  `Web-Net-Ext45`

## Usage

```hcl
module "web01" {
  source = "./aws/windows-2025-core-iis-base"

  name_prefix = "web01"
  aws_region  = "us-east-1"

  admin_source_cidr_blocks = ["203.0.113.10/32"] # your Ansible control node
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

- **Verify `ami_name_filter`** for your region:
  ```sh
  aws ec2 describe-images --owners amazon \
    --filters "Name=name,Values=Windows_Server-2025-English-Core-Base-*" \
    --query 'Images[].Name' --region <region>
  ```
- **Protect Terraform state.** If `admin_password` is left unset, a random
  password is generated and stored in state as the sensitive
  `admin_password` output (needed as a break-glass credential; day-to-day
  access is via SSH key). Use a remote backend with encryption and
  restricted access.

## Inputs / outputs

See `variables.tf` and `outputs.tf` for the full list.

# ubuntu-2604-minimal-apache-base (AWS)

A tightly locked down Ubuntu 26.04 LTS minimal server on AWS, with Apache
pre-installed, intended as the starting point for further configuration via
Ansible over SSH. This is the AWS counterpart to
`../../azure/ubuntu-2604-minimal-apache-base` and follows the same security
model.

## Security posture

- **Key-only SSH.** The instance's SSH key comes from an `aws_key_pair`
  built from `ssh_public_key` (Canonical's cloud-init default `ubuntu` user
  picks it up automatically). Cloud-init additionally hardens
  `sshd_config` (`PermitRootLogin no`, `PasswordAuthentication no`,
  `KbdInteractiveAuthentication no`) and restarts `ssh` to apply it.
- **No open access by default.** `admin_source_cidr_blocks` has no default
  and must be set explicitly - point it at your Ansible control node(s) or
  management VPN/jump host range. There is no Elastic IP unless
  `enable_public_ip = true`.
- **Security group** allows only SSH (from the admin allow-list) and
  HTTP/HTTPS (from `web_source_cidr_blocks`, defaulting to the internet,
  since this is a web server, but only reachable once a public IP exists).
- **Host firewall (ufw)** mirrors the security group: default-deny inbound,
  default allow outbound, explicit allows for 22/80/443 only.
- **fail2ban** (on by default) mitigates SSH brute-force attempts.
- **unattended-upgrades** (on by default) applies security patches
  automatically.
- **EBS root volume is encrypted** and **IMDSv2 is enforced**
  (`http_tokens = "required"`).
- Apache is minimally configured: `ServerTokens Prod`, `ServerSignature Off`,
  `TraceEnable Off` to avoid leaking version/banner information.

Everything above is infrastructure/host-layer lockdown. Site configuration,
TLS certificates, and further OS hardening are expected to be layered on
afterwards via Ansible over the SSH connection this template sets up.

## Networking and internet egress - read this before applying

Unlike Azure, AWS instances without a public/Elastic IP have **no outbound
internet access at all** unless something provides it (NAT gateway,
existing VPC egress, etc). Cloud-init's `apt` package installs/upgrades
need internet access the first time they run, so this template provisions
its own NAT gateway by default (`enable_nat_gateway = true`) when
`enable_public_ip = false`, so the instance stays unreachable from the
internet while still being able to provision itself correctly.

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
  otherwise `package_update`/`package_upgrade` and the `apache2`/
  `fail2ban`/`unattended-upgrades` installs in cloud-init will fail.

## Usage

```hcl
module "web01" {
  source = "./aws/ubuntu-2604-minimal-apache-base"

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
and `admin_username` outputs, with `ansible_connection: ssh`.

## Before you apply

- **Verify `ami_name_filter`** for your region - the codename segment is
  wildcarded on purpose since it isn't guessed here:
  ```sh
  aws ec2 describe-images --owners 099720109477 \
    --filters "Name=name,Values=ubuntu-minimal/images/hvm-ssd-gp3/ubuntu-*-26.04-amd64-minimal-*" \
    --query 'Images[].Name' --region <region>
  ```
  If `26.04` isn't published yet in your region/account at apply time,
  override `ami_name_filter` to pin `24.04` until it is.

## Inputs / outputs

See `variables.tf` and `outputs.tf` for the full list.

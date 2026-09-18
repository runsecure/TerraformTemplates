# ubuntu-2604-minimal-apache-base (GCP)

A tightly locked down Ubuntu 26.04 LTS minimal server on Google Cloud, with
Apache pre-installed, intended as the starting point for further
configuration via Ansible over SSH. This follows the same security model as
the Azure and AWS counterparts in this repo.

## Security posture

- **Key-only SSH.** The SSH key comes from the instance's `ssh-keys`
  metadata (`admin_username:ssh_public_key`); the GCE guest agent creates
  that user and installs the key automatically. `block-project-ssh-keys`
  is set so project-wide SSH keys can't also grant access to this
  instance. Cloud-init additionally hardens `sshd_config`
  (`PermitRootLogin no`, `PasswordAuthentication no`,
  `KbdInteractiveAuthentication no`) and restarts `ssh` to apply it.
- **No open access by default.** `admin_source_cidr_ranges` has no default
  and must be set explicitly - point it at your Ansible control node(s) or
  management VPN/Cloud Interconnect range. There is no external IP unless
  `enable_public_ip = true`.
- **Custom-mode VPC** with no default-allow rules: only what's explicitly
  opened here (SSH from the admin allow-list, HTTP/HTTPS from
  `web_source_cidr_ranges`) is reachable, gated by a firewall target tag
  applied only to this instance.
- **Host firewall (ufw)** mirrors the network layer: default-deny inbound,
  default allow outbound, explicit allows for 22/80/443 only.
- **fail2ban** (on by default) mitigates SSH brute-force attempts.
- **unattended-upgrades** (on by default) applies security patches
  automatically.
- **Shielded VM** (Secure Boot + vTPM + integrity monitoring) is enabled by
  default.
- **No service account is attached** to the instance, so it has no GCP API
  access by default.
- Apache is minimally configured: `ServerTokens Prod`, `ServerSignature Off`,
  `TraceEnable Off` to avoid leaking version/banner information.

Everything above is infrastructure/host-layer lockdown. Site configuration,
TLS certificates, and further OS hardening are expected to be layered on
afterwards via Ansible over the SSH connection this template sets up.

## Networking and internet egress

Cloud-init's `apt` package installs/upgrades need internet access the
first time they run. This template does not provision Cloud NAT. If
`enable_public_ip = false` and your project/VPC doesn't otherwise provide
egress, those installs may fail - add Cloud NAT, or set
`enable_public_ip = true`, if you hit this.

## Sizing and storage

- **`machine_type`** controls vCPU and memory together via a predefined
  catalog SKU. GCP also lets you dial them independently with a **custom
  machine type**: set both `custom_cpu_count` and `custom_memory_mb` to
  build `custom-<cpus>-<memory_mb>` (this overrides `machine_type`
  entirely).
- **`boot_disk_size_gb`** / **`boot_disk_type`** control the boot disk.
- **`data_disks`** attaches additional empty persistent disks beyond the
  boot disk (each `{ size_gb, type }`). cloud-init formats each one ext4
  and mounts it under `/mnt/dataN` automatically. See the `data_disk_ids`
  output.
- **`additional_mounts`** mounts *existing* network storage inside the
  instance at boot - an NFS export (Filestore, etc.), an SMB/CIFS share,
  or an S3(-compatible) bucket (via `s3fs`). This does not provision the
  storage itself. Example:
  ```hcl
  additional_mounts = [
    { type = "nfs", source = "10.0.0.4:/vol1", mount_point = "/mnt/shared" },
  ]
  ```

## Usage

```hcl
module "web01" {
  source = "./gcp/ubuntu-2604-minimal-apache-base"

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
and `admin_username` outputs, with `ansible_connection: ssh`.

## Before you apply

- **Verify `image_family`** for your project's image access:
  ```sh
  gcloud compute images list --project ubuntu-os-cloud --filter="family~2604" --format="table(name,family)"
  ```
  If `ubuntu-minimal-2604-lts-amd64` isn't published yet, override
  `image_family` to `ubuntu-minimal-2404-lts-amd64` until it is.

## Inputs / outputs

See `variables.tf` and `outputs.tf` for the full list.

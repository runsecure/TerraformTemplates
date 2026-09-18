terraform {
  required_version = ">= 1.7.0"

  required_providers {
    vsphere = {
      source  = "hashicorp/vsphere"
      version = "~> 2.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Reads VSPHERE_SERVER / VSPHERE_USER / VSPHERE_PASSWORD from the
# environment - do not hardcode vCenter credentials here or in tfvars.
provider "vsphere" {
  allow_unverified_ssl = var.vsphere_allow_unverified_ssl
}

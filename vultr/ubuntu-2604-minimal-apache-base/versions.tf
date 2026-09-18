terraform {
  required_version = ">= 1.7.0"

  required_providers {
    vultr = {
      source  = "vultr/vultr"
      version = ">= 2.0"
    }
  }
}

# Reads VULTR_API_KEY from the environment - do not hardcode an API key
# here or in tfvars. This matches the ambient-credentials pattern used by
# the AWS/Azure/GCP templates in this repo.
provider "vultr" {}

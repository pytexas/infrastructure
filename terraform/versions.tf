# ABOUTME: Terraform and provider version constraints for the PyTexas infra stack.
# Pinned to the digitalocean provider; state is local for now.

terraform {
  required_version = ">= 1.6"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

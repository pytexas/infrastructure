# ABOUTME: DigitalOcean Spaces bucket holding this configuration's own terraform state.
# Self-referential: after the first apply, `terraform init -migrate-state` moves local
# state into this bucket.
#
# The Spaces ACCESS KEY used to read/write state lives outside terraform -- you create
# it once in the DO console (https://cloud.digitalocean.com/spaces/access_keys) and put
# its access-key-id + secret-key into secrets/terraform.sops.env. We don't try to
# terraform-manage that key at our scale; it's not worth the moving part.

resource "digitalocean_spaces_bucket" "tfstate" {
  name   = var.tfstate_bucket_name
  region = var.region
  acl    = "private"

  versioning {
    enabled = true
  }

  # Refuse to delete unless empty. Prevents accidental loss of state history.
  force_destroy = false
}

# ABOUTME: Remote state backend pointing at the Spaces bucket created in spaces.tf.
#
# This file is named *.tf.disabled so terraform does NOT load it during the
# initial bootstrap (terraform only auto-loads files ending in .tf). The
# `-backend=false` init flag alone is not enough -- terraform still reads
# backend.tf on subsequent plan/apply calls and demands re-init.
#
# Bootstrap sequence:
#   1. `just tf-init-bootstrap`        -- terraform init with backend.tf hidden
#   2. `just tf-apply`                 -- creates bucket + access key + droplet (LOCAL state)
#   3. `just tf-capture-spaces-creds`  -- writes outputs into ../secrets/terraform.sops.env
#   4. `just tf-enable-backend`        -- renames this file to backend.tf
#   5. `just tf-init-migrate`          -- copies local state into the bucket
#
# After step 5, backend.tf exists and every subsequent terraform command uses
# the remote state.
#
# Terraform backend blocks do NOT accept variables, so the bucket name + region
# are duplicated here -- keep them in sync with var.tfstate_bucket_name and
# var.region.

terraform {
  backend "s3" {
    bucket = "pytexas-tfstate" # KEEP IN SYNC WITH var.tfstate_bucket_name
    key    = "terraform.tfstate"

    # DO Spaces endpoint shape -- the s3 backend takes the region's endpoint here.
    # If you change var.region, change this endpoint too.
    endpoints = {
      s3 = "https://sfo3.digitaloceanspaces.com"
    }

    # `region` is required by the S3 backend but ignored by DO Spaces.
    region = "us-east-1"

    # DO Spaces doesn't expose the AWS metadata APIs the S3 backend tries to probe.
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}

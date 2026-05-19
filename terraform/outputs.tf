# ABOUTME: Outputs consumed by ansible (via inventory templating) and humans.
# Run `terraform output -json` to feed these into the inventory.

output "droplet_id" {
  description = "Numeric DigitalOcean ID of the droplet."
  value       = digitalocean_droplet.main.id
}

output "droplet_name" {
  description = "Hostname of the droplet."
  value       = digitalocean_droplet.main.name
}

output "droplet_ipv4" {
  description = "Public IPv4 address."
  value       = digitalocean_droplet.main.ipv4_address
}

output "droplet_ipv6" {
  description = "Public IPv6 address."
  value       = digitalocean_droplet.main.ipv6_address
}

output "droplet_region" {
  description = "Region the droplet is deployed in."
  value       = digitalocean_droplet.main.region
}

output "infra_fqdn" {
  description = "Fully-qualified hostname of the infra droplet (A/AAAA records pointed at it). Should match MIDDLEWARE_DOMAIN in secrets/pytexas.sops.env."
  value       = digitalocean_record.infra_a.fqdn
}

# --- Spaces (terraform state backend) -------------------------------------

output "tfstate_bucket_name" {
  description = "Name of the Spaces bucket holding terraform state."
  value       = digitalocean_spaces_bucket.tfstate.name
}

output "tfstate_bucket_endpoint" {
  description = "S3-compatible endpoint URL for the state bucket. Use this verbatim in backend.tf if you ever change region."
  value       = "https://${digitalocean_spaces_bucket.tfstate.region}.digitaloceanspaces.com"
}

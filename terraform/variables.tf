# ABOUTME: Input variables for the PyTexas DigitalOcean stack.
# Most have sane defaults; secrets (do_token) and the SSH key name must be supplied.

variable "do_token" {
  description = "DigitalOcean API token. Set via the TF_VAR_do_token env var (terraform's convention), not DIGITALOCEAN_TOKEN."
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "DigitalOcean project name used to group resources in the UI."
  type        = string
  default     = "Infrastructure"
}

variable "environment" {
  description = "Environment tag applied to all resources. Must be one of production/staging/development to satisfy the DigitalOcean project resource."
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "development"], var.environment)
    error_message = "environment must be one of: production, staging, development."
  }
}

variable "droplet_name" {
  description = "Hostname for the primary droplet."
  type        = string
  default     = "pytexas-1"
}

variable "region" {
  description = "DigitalOcean region slug. Used for the droplet and the Spaces assets bucket."
  type        = string
  default     = "sfo3"
}

variable "assets_bucket_name" {
  description = "Globally unique name for the public DigitalOcean Spaces bucket holding web assets (page images, meetup banners, etc.)."
  type        = string
  default     = "pytexas-assets"
}

variable "droplet_size" {
  description = "Droplet size slug. s-2vcpu-2gb is the cost/perf sweet spot for the current workload."
  type        = string
  default     = "s-2vcpu-2gb"
}

variable "droplet_image" {
  description = "Base image slug. Stick to current LTS."
  type        = string
  default     = "ubuntu-24-04-x64"
}

variable "enable_backups" {
  description = "Whether to enable DO weekly backups (~20% of droplet cost)."
  type        = bool
  default     = true
}

variable "enable_monitoring" {
  description = "Whether to enable the DO monitoring agent (free)."
  type        = bool
  default     = true
}

variable "allowed_ssh_cidrs" {
  description = "CIDRs allowed to reach SSH on port 22. Default is open; tighten once Tailscale is up by either restricting to your tailnet exit IPs or removing port 22 entirely in favor of `tailscale ssh`."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "expose_http" {
  description = "Whether to open 80/443 to the public internet. Required for Caddy + Let's Encrypt; leave true unless you intend all services to be tailnet-only."
  type        = bool
  default     = true
}

variable "dns_domain" {
  description = "Base domain whose DNS zone is already managed in DigitalOcean (registrar NS pointing at DO). Terraform creates A/AAAA records inside this zone but does NOT manage the zone itself."
  type        = string
  default     = "pytx.org"
}

variable "infra_subdomain" {
  description = "Subdomain (under dns_domain) that resolves to the droplet. Used by Caddy on the droplet to terminate TLS and reverse-proxy to backend containers. Must match MIDDLEWARE_DOMAIN in secrets/pytexas.sops.env."
  type        = string
  default     = "infra"
}

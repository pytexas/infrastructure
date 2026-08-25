# ABOUTME: Primary infrastructure for PyTexas Foundation -- one droplet, one firewall, one project.
# Optimized for cost and simplicity. Scale by adding sibling droplets, not by resizing this one.

locals {
  common_tags = [
    "pytexas",
    "env:${var.environment}",
    "managed-by:terraform",
  ]
}

# Authorize every SSH key already uploaded to the DO account. Simpler than picking
# names; if you want to restrict, add a `filter { key = "name", values = [...] }`
# block to the data source.
data "digitalocean_ssh_keys" "all" {
  sort {
    key       = "name"
    direction = "asc"
  }
}

resource "digitalocean_droplet" "main" {
  name       = var.droplet_name
  region     = var.region
  size       = var.droplet_size
  image      = var.droplet_image
  backups    = var.enable_backups
  monitoring = var.enable_monitoring
  ipv6       = true

  # DO no longer enables backups from the bare `backups = true` toggle alone -- it needs a
  # policy. Weekly keeps cost down (~$1/mo at this size) vs daily. Only set when backups are on.
  dynamic "backup_policy" {
    for_each = var.enable_backups ? [1] : []
    content {
      plan    = "weekly"
      weekday = "SUN"
      hour    = 8
    }
  }

  ssh_keys = [for k in data.digitalocean_ssh_keys.all.ssh_keys : k.id]

  tags = concat(local.common_tags, ["role:app"])
}

resource "digitalocean_firewall" "main" {
  name        = "${var.droplet_name}-fw"
  droplet_ids = [digitalocean_droplet.main.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.allowed_ssh_cidrs
  }

  dynamic "inbound_rule" {
    for_each = var.expose_http ? ["80", "443"] : []
    content {
      protocol         = "tcp"
      port_range       = inbound_rule.value
      source_addresses = ["0.0.0.0/0", "::/0"]
    }
  }

  # Tailscale direct connections (UDP 41641) -- lets the tailnet establish
  # direct peer-to-peer paths rather than relaying through DERP.
  inbound_rule {
    protocol         = "udp"
    port_range       = "41641"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

resource "digitalocean_project" "main" {
  name        = var.project_name
  description = "PyTexas Foundation infrastructure"
  purpose     = "Operational / Developer tooling"
  environment = title(var.environment)
  resources = [
    digitalocean_droplet.main.urn,
    digitalocean_spaces_bucket.assets.urn,
    # Domain itself is managed outside terraform, but DO auto-attaches any
    # domain that has records to whichever project owns it. List the URN here
    # so terraform doesn't keep trying to remove it.
    "do:domain:${var.dns_domain}",
  ]
  # Firewalls don't have URNs and can't be assigned to projects directly --
  # they're grouped implicitly through the droplets they attach to.

  # DO requires exactly one default project per account; we don't try to manage
  # which project is the default from terraform (DO will keep this one as the
  # default until you mark another one in the console).
  lifecycle {
    ignore_changes = [is_default]
  }
}

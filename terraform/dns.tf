# ABOUTME: DNS records pointing the infra subdomain at the droplet. The zone itself
# (var.dns_domain) is managed outside terraform -- you registered the domain at some
# registrar and pointed its NS records at DigitalOcean's nameservers. Terraform only
# creates leaf records inside the zone.

resource "digitalocean_record" "infra_a" {
  domain = var.dns_domain
  type   = "A"
  name   = var.infra_subdomain
  value  = digitalocean_droplet.main.ipv4_address
  ttl    = 300
}

resource "digitalocean_record" "infra_aaaa" {
  domain = var.dns_domain
  type   = "AAAA"
  name   = var.infra_subdomain
  value  = digitalocean_droplet.main.ipv6_address
  ttl    = 300
}

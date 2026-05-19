# ABOUTME: DigitalOcean provider configuration.
# Token comes from the TF_VAR_do_token env var (or set do_token in terraform.tfvars).

provider "digitalocean" {
  token = var.do_token
}

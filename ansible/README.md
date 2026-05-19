# Ansible

Configures the droplet(s) terraform creates: hardens SSH, installs Docker, joins the tailnet, and clones the service repos.

## Prereqs

- Ansible >= 2.16
- `ansible-galaxy collection install -r requirements.yml` (installs `community.sops`,
  `community.docker`, `community.general`, `ansible.posix`)
- An age keypair at `~/.config/sops/age/keys.txt` (see `../secrets/README.md`)
- `secrets/ansible.sops.yaml` populated with `tailscale_auth_key`
  (or, as a fallback, the `TAILSCALE_AUTH_KEY` env var exported in your shell)

## Inventory

`inventory.yml` is committed with `REPLACE_WITH_DROPLET_IPV4` as a placeholder. Three options:

1. **Quick**: edit `inventory.yml` directly after `terraform apply`.
2. **Repeatable**: copy to `inventory.local.yml` (gitignored) and use `-i inventory.local.yml`.
3. **Automated**: pipe `terraform output -raw droplet_ipv4` into a generated inventory (see `justfile`).

## Running

```bash
# pre_tasks load tailscale_auth_key from ../secrets/ansible.sops.yaml automatically.
# If you prefer not to commit it yet, export TAILSCALE_AUTH_KEY in your shell instead.

# Dry run first
ansible-playbook playbook.yml --check --diff

# For real
ansible-playbook playbook.yml
```

Run specific roles with tags:

```bash
ansible-playbook playbook.yml --tags bootstrap,docker
```

## Roles, in order

1. **bootstrap** -- baseline packages, deploy user, SSH lockdown (no root, no passwords), unattended-upgrades, fail2ban.
2. **docker** -- Docker CE + compose plugin from Docker's official apt repo.
3. **tailscale** -- installs tailscale, enables IP forwarding, runs `tailscale up` with the supplied auth key. Tailscale SSH is enabled by default so you can drop port 22 from the cloud firewall after the first run.
4. **services** -- clones the service repos into `/srv/pytexas/<name>` and drops the master `compose/docker-compose.yml` next to them. **Does not** run `docker compose up` yet -- the per-service refactor (moving each repo's temporal/caddy behind a `standalone` profile) lands next.

## What this does NOT do

- Open / close firewall ports on the droplet itself (we rely on the DigitalOcean cloud firewall managed by terraform).
- Manage container secrets / `.env` files. Those will be handled with `ansible-vault` or sops once we wire compose-up.
- Configure DNS records.

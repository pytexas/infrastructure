# Ansible

Configures the droplet terraform creates: hardens SSH, installs Docker + Tailscale,
clones the infrastructure repo and service repos into `/srv/pytexas`, pushes decrypted
secrets, and brings up the unified docker compose stack.

Normally you don't run ansible directly — `just apply` (from `bootstrap/`) renders the
inventory from terraform output and runs the playbook. The commands below are for when
you want to drive it by hand.

## Prereqs

- Ansible >= 2.16
- `just setup` (from `bootstrap/`) — installs `community.sops`, `community.docker`,
  `community.general`, `ansible.posix`. Equivalent to
  `ansible-galaxy collection install -r requirements.yml`.
- An age keypair at `~/.config/sops/age/keys.txt` (see `../secrets/README.md`)
- `secrets/ansible.sops.yaml` populated with `tailscale_auth_key`
  (or, as a fallback, the `TAILSCALE_AUTH_KEY` env var exported in your shell)

## Inventory

`inventory.yml` is committed with `REPLACE_WITH_DROPLET_IPV4` as a placeholder.
`just apply` renders `inventory.local.yml` (gitignored) from
`terraform output -raw droplet_ipv4` automatically. To run by hand:

```bash
ip=$(cd ../terraform && sops exec-env ../secrets/terraform.sops.env 'terraform output -raw droplet_ipv4')
sed "s/REPLACE_WITH_DROPLET_IPV4/$ip/" inventory.yml > inventory.local.yml
```

## Running by hand

```bash
# Dry run first
ansible-playbook -i inventory.local.yml playbook.yml --check --diff

# For real
ansible-playbook -i inventory.local.yml playbook.yml

# Just one role
ansible-playbook -i inventory.local.yml playbook.yml --tags bootstrap,docker

# Skip the compose-up step (deploy files/config without restarting containers)
ansible-playbook -i inventory.local.yml playbook.yml --skip-tags compose-up
```

The `tailscale_auth_key` is loaded from `../secrets/ansible.sops.yaml` by the playbook's
`pre_tasks` via `community.sops.load_vars`. The `TAILSCALE_AUTH_KEY` env var is honored
as a fallback if the sops file is absent.

## Roles, in order

1. **bootstrap** — baseline packages (incl. `just`), deploy user `pytexas`, SSH lockdown
   (no root, no passwords), unattended-upgrades, fail2ban. Waits on `cloud-init status
   --wait` first to avoid first-boot apt lock contention.
2. **docker** — Docker CE + compose plugin from Docker's official apt repo.
3. **tailscale** — installs tailscale, enables IP forwarding, runs `tailscale up` with
   the supplied auth key and `--ssh`. Tailscale SSH lets you drop port 22 from the cloud
   firewall after the first run.
4. **services** — clones the infrastructure repo into `/srv/pytexas` and the service
   repos as subdirectories, decrypts the sops `.env` files on the controller and pushes
   plaintext to the droplet at `mode 0600`, then brings up the unified compose project
   (`docker compose up -d`). Also sets the Temporal namespace retention.

## What this does NOT do

- Open / close firewall ports on the droplet itself — we rely on the DigitalOcean cloud
  firewall managed by terraform.
- Manage the DNS zone — terraform owns the `infra.pytx.org` records.
- Hold any decryption key on the droplet — sops decryption happens on the controller
  (your laptop) and only plaintext `.env` files land on the droplet.

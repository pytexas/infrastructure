# Terraform

Manages the PyTexas DigitalOcean footprint:
**one droplet**, **one cloud firewall**, **one DO project** for grouping, **DNS records**
for `infra.pytx.org`, and **one public Spaces bucket** for web assets.

Terraform state is **sops-encrypted and committed to this repo** (`terraform/state.sops.json`).
There is no remote backend and no self-referential state bucket -- state is just another
encrypted file, like the secrets.

## Prereqs

- Terraform >= 1.6
- A DigitalOcean API token with read/write
- A Spaces access key (separate from the API token -- see below), used to manage the assets
  bucket over the S3 API and to upload assets
- Your age private key at `~/.config/sops/age/keys.txt` (to decrypt state + secrets)
- Your SSH key uploaded to your DO account (`data.digitalocean_ssh_keys.all` authorizes
  every key in the account on the droplet)

## State: sops-encrypted in git

State lives at `terraform/state.sops.json`, encrypted whole-file with age via sops. Every
terraform command runs through the `_tf` wrapper in `bootstrap/justfile`, which:

1. decrypts `state.sops.json` into terraform's working `terraform.tfstate`,
2. runs the terraform command (with the DO token + Spaces key decrypted into the env),
3. re-encrypts `state.sops.json` in place **only if the state actually changed** -- so
   read-only commands (`plan`, `output`) don't churn git, and a new sops nonce isn't written
   on every run. Re-encryption also happens when terraform exits non-zero, so a partial
   apply's state is captured.

**After any apply that changed state, commit `terraform/state.sops.json`.** The wrapper
prints a reminder to stderr when it re-encrypts.

Because state is local (decrypted only transiently), there is **no state locking**. That's
fine for a solo or coordinated operator; don't run `apply` from two machines at once, and
don't apply on two branches in parallel (the encrypted blob won't merge).

### Two kinds of DigitalOcean credentials

1. **DO API token** -- bearer token for `api.digitalocean.com` (droplets, firewalls,
   projects, DNS). Terraform reads it from `TF_VAR_do_token`.
2. **Spaces access key** -- AWS-style key pair for the S3 protocol at
   `*.digitaloceanspaces.com`. Terraform uses it to create/manage the assets bucket, and
   asset uploaders use it to write files. Generate at
   **<https://cloud.digitalocean.com/spaces/access_keys>** -- a *separate page* from API
   tokens. Set `SPACES_ACCESS_KEY_ID` + `SPACES_SECRET_ACCESS_KEY`.

Both live in `secrets/terraform.sops.env`; the `just` recipes decrypt them into the terraform
process via `sops exec-env`. You don't export anything yourself.

## Day-1 (fresh clone) and day-2

```bash
cd terraform && terraform init && cd ..   # one-time: install provider plugins
cd bootstrap
just apply        # terraform apply + ansible (full deploy). Idempotent.
just plan         # preview, no apply
just ip           # droplet public IPv4
just destroy      # see caveats below
```

No init dance, no state migration, no backend file. `just apply` on a fresh clone with no
`state.sops.json` yet just creates everything and writes the first encrypted state.

## The public assets bucket

`digitalocean_spaces_bucket.assets` (default name `pytexas-assets`) holds public-facing web
assets -- page images, meetup banners, etc.

- **Public read, no listing:** a `digitalocean_spaces_bucket_policy` grants anonymous
  `s3:GetObject` on every object, so files load by direct URL. The bucket ACL stays private,
  so the bucket isn't listable.
- **Writes require the Spaces key.** Upload with any S3 client pointed at
  `https://sfo3.digitaloceanspaces.com` using the `SPACES_*` credentials.
- **Public URL:** `https://<bucket>.<region>.digitaloceanspaces.com/<object-key>` (see the
  `assets_bucket_endpoint` output).
- CORS allows `GET`/`HEAD` from any origin so assets embed cross-site.

## What the firewall opens

| Port    | Protocol | Source              | Why                                                          |
|---------|----------|---------------------|--------------------------------------------------------------|
| 22      | TCP      | `allowed_ssh_cidrs` | SSH. Narrow after tailscale is up, or drop entirely and use `tailscale ssh`. |
| 80, 443 | TCP      | `0.0.0.0/0`         | Caddy + Let's Encrypt. Toggle off with `expose_http = false`. |
| 41641   | UDP      | `0.0.0.0/0`         | Tailscale direct peer connections (NAT traversal).           |
| ICMP    | -        | `0.0.0.0/0`         | Ping.                                                        |

Outbound is wide open.

## Rebuilding vs. destroying

### Rebuild the droplet (common) -- keeps DNS, the assets bucket, and state

```bash
cd bootstrap
just rebuild     # terraform apply -replace=digitalocean_droplet.main
just apply       # re-run ansible against the fresh droplet
```

`-replace` destroys and recreates only the droplet; the firewall, project, DNS records, and
assets bucket are untouched (the DNS records auto-update to the new IP).

### Full teardown (rare)

`just destroy` removes the droplet, firewall, and DNS records. Two caveats:

- **The DO default project can't be deleted.** A plain `terraform destroy` fails on it. If
  you truly want to tear everything down, drop it from state first and re-import later:

  ```bash
  just _tf 'state rm digitalocean_project.main'
  just destroy
  # later, to manage it again:
  just _tf 'import digitalocean_project.main <project-id>'
  ```

- **The assets bucket must be empty to delete.** `digitalocean_spaces_bucket.assets` has no
  `force_destroy`, so destroy fails if it holds objects (deliberate -- don't nuke published
  assets by accident). Empty it first, or add `force_destroy = true` consciously.

State is in git, so there's nothing to migrate before a destroy.

## What this does NOT manage

- **The DNS zone itself.** `pytx.org` is managed in DigitalOcean outside terraform (the
  registrar's NS records point at DO). Terraform only creates leaf records
  (`infra.pytx.org` A + AAAA) inside the existing zone -- no `digitalocean_domain` resource,
  so a `terraform destroy` can't accidentally delete the zone.
- **The Spaces access key.** Created once in the DO console; not terraform-managed.
- **Reserved IPs** (extra $4/mo; skip unless we need a stable IP across droplet recreates).

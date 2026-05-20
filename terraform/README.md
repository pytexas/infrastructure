# Terraform

Manages the PyTexas DigitalOcean footprint as a single self-referential config:
**one droplet**, **one cloud firewall**, **one DO project** for grouping, **DNS records**
for `infra.pytx.org`, and **one Spaces bucket** holding this config's own terraform state.

Everything lives in one state file. The bucket-that-holds-the-state is itself a resource
in that state file (the classic Terraform self-reference trick).

## Prereqs

- Terraform >= 1.6
- A DigitalOcean API token with read/write
- A Spaces access key (separate from the API token — see below)
- Your SSH key uploaded to your DO account (`data.digitalocean_ssh_keys.all` authorizes
  every key in the account on the droplet)

## First-time bootstrap (chicken-and-egg dance)

The Spaces bucket can't hold state until it exists, so the very first apply runs with
**local state** and a follow-up `terraform init` migrates that state into Spaces once
the bucket is real. To keep terraform from trying to use the backend before the bucket
exists, the backend config lives in `backend.tf.disabled` (terraform only auto-loads
files ending in `.tf`). It's renamed into place after the bucket has been created.

### Two kinds of DigitalOcean credentials

The bootstrap needs both:

1. **DO API token** — bearer token for `api.digitalocean.com`. Used for droplets,
   firewalls, projects, DNS records. Generate at
   <https://cloud.digitalocean.com/account/api/tokens>, "All permissions" is easiest.
   Terraform reads it from `TF_VAR_do_token`:

   ```bash
   export TF_VAR_do_token=dop_v1_xxxxxxxxxxxx
   ```

2. **Spaces access key** — AWS-style access-key-id + secret pair for the S3 protocol at
   `*.digitaloceanspaces.com`. This is what terraform uses to **create** the bucket (the
   S3 endpoint, not the platform API) AND what the s3 backend uses to read/write state.
   Generate at **<https://cloud.digitalocean.com/spaces/access_keys>** — a *separate page*
   from API tokens. Copy both halves immediately (the secret is shown once):

   ```bash
   export SPACES_ACCESS_KEY_ID=DO00...
   export SPACES_SECRET_ACCESS_KEY=...
   ```

The same Spaces key continues to serve as the backend's auth credential after bootstrap
— there's no separate terraform-managed scoped key. To rotate, generate a new key in the
DO console, update `secrets/terraform.sops.env`, redeploy.

### The bootstrap sequence

Run from `bootstrap/` unless noted. The full annotated version is in the repo-root
`README.md`; the short form:

```bash
# 1. Init with local state. backend.tf is named backend.tf.disabled so terraform
#    ignores it. Run raw terraform for this step (from terraform/):
cd ../terraform && terraform init && cd ../bootstrap

# 2. First apply -- creates droplet + firewall + project + DNS + Spaces bucket.
just apply

# 3. Put the three credentials into the encrypted env file (TF_VAR_do_token,
#    SPACES_ACCESS_KEY_ID, SPACES_SECRET_ACCESS_KEY, plus AWS_ACCESS_KEY_ID and
#    AWS_SECRET_ACCESS_KEY mirroring the SPACES_ values for the s3 backend).
just sops secrets/terraform.sops.env

# 4. Enable the backend and migrate local state into the bucket.
mv ../terraform/backend.tf.disabled ../terraform/backend.tf
cd ../terraform && \
    sops exec-env ../secrets/terraform.sops.env 'terraform init -migrate-state'
```

After migration, the local `terraform.tfstate` is obsolete (a `*.backup` is left behind —
safe to delete once you've confirmed the bucket has the real state). Commit
`terraform/backend.tf` (now enabled) so the next operator clones a repo already wired for
the remote backend.

## Day-2

Every subsequent terraform command runs through `bootstrap/justfile`, which wraps
terraform with `sops exec-env` so the DO token + Spaces key are decrypted from
`secrets/terraform.sops.env` into the child process. You don't export anything yourself:

```bash
cd bootstrap
just plan       # terraform plan
just apply      # terraform apply + ansible (full deploy)
just ip         # droplet public IPv4
just destroy    # see caveat below
```

## What the firewall opens

| Port    | Protocol | Source              | Why                                                          |
|---------|----------|---------------------|--------------------------------------------------------------|
| 22      | TCP      | `allowed_ssh_cidrs` | SSH. Narrow after tailscale is up, or drop entirely and use `tailscale ssh`. |
| 80, 443 | TCP      | `0.0.0.0/0`         | Caddy + Let's Encrypt. Toggle off with `expose_http = false`. |
| 41641   | UDP      | `0.0.0.0/0`         | Tailscale direct peer connections (NAT traversal).           |
| ICMP    | -        | `0.0.0.0/0`         | Ping.                                                        |

Outbound is wide open.

## Destroy ordering caveat

Because the bucket holding the state is itself a resource in that state, a naive
`terraform destroy` tries to delete the bucket and then fails to write the final state
update. To fully tear down, migrate state back to local first:

```bash
# 1. Disable the backend and pull state back to local so terraform isn't deleting
#    its own backend mid-destroy.
mv terraform/backend.tf terraform/backend.tf.disabled
cd terraform && terraform init -migrate-state   # copies remote state back to local

# 2. Now destroy with local state (export TF_VAR_do_token + SPACES_* first, since the
#    sops-wrapped recipe relies on the bucket that's about to vanish).
terraform destroy
```

You'll almost certainly never need this for PyTexas. Documented for completeness.

## What this does NOT manage

- **The DNS zone itself.** `pytx.org` is managed in DigitalOcean outside terraform (the
  registrar's NS records point at DO). Terraform only creates leaf records
  (`infra.pytx.org` A + AAAA) inside the existing zone — no `digitalocean_domain`
  resource, so a `terraform destroy` can't accidentally delete the zone.
- **Reserved IPs** (extra $4/mo; skip unless we need a stable IP across droplet recreates).

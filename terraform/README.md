# Terraform

Manages the PyTexas DigitalOcean footprint as a single self-referential config:
**one droplet**, **one cloud firewall**, **one DO project** for grouping, **one Spaces
bucket** holding this config's own terraform state, and **one access key** scoped to
that bucket.

Everything lives in one state file. The bucket-that-holds-the-state is itself a resource
in that state file (the classic Terraform self-reference trick).

## Prereqs

- Terraform >= 1.6
- A DigitalOcean API token with read/write
- At least one SSH key already uploaded to your DO account (the name goes in `ssh_key_names`)

## First-time bootstrap (chicken-and-egg dance)

The Spaces bucket can't hold state until it exists, so the very first apply runs with
**local state** and a follow-up `terraform init` migrates that state into Spaces once
the bucket is real. To keep terraform from trying to use the backend before the bucket
exists, the backend config lives in `backend.tf.disabled` (terraform only auto-loads
files ending in `.tf`). It's renamed into place after the bucket has been created.

### Prerequisites: two kinds of DigitalOcean credentials

DigitalOcean has two separate credential types and the bootstrap needs both:

1. **DO API token** — bearer token for `api.digitalocean.com`. Used for droplets,
   firewalls, projects, and (later) terraform-managing Spaces access keys. Generate at
   <https://cloud.digitalocean.com/account/api/tokens>. Scopes needed:
   `droplet`, `firewall`, `project`, `tag`, `ssh_key`, `spaces_key`. Easiest is
   "All permissions". Export as:

   ```bash
   export TF_VAR_do_token=dop_v1_xxxxxxxxxxxx
   ```

2. **Spaces access key** — AWS-style access-key-id + secret-key pair for the S3
   protocol at `*.digitaloceanspaces.com`. This is what terraform uses to **create**
   the bucket itself (the S3 endpoint, not the DO platform API). Generate at
   **<https://cloud.digitalocean.com/spaces/access_keys>** -- a *separate page* from
   the API tokens above. Name it `terraform-bootstrap`, "All permissions". Copy both
   halves immediately (the secret is shown only once). Export as:

   ```bash
   export SPACES_ACCESS_KEY_ID=DO00...
   export SPACES_SECRET_ACCESS_KEY=...
   ```

The Spaces access key only needs to exist for the bootstrap. After step 5 below, the
terraform-managed scoped key (in `secrets/terraform.sops.env`) takes over for state
operations, and you can revoke the bootstrap key in the DO console if you want -- as
long as you keep one Spaces key around for terraform itself to use on subsequent
applies (the s3 backend needs Spaces creds for state read/write).

### The four-command dance

Run from the repo root:

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
$EDITOR terraform/terraform.tfvars   # tweak overrides if you want; all values have defaults

# 1. Init with local state (backend.tf.disabled is invisible to terraform).
just tf-init-bootstrap

# 2. First apply -- creates droplet + firewall + project + Spaces bucket.
just tf-apply

# 3. Populate secrets/terraform.sops.env with TF_VAR_do_token,
#    AWS_ACCESS_KEY_ID (= the SPACES_ACCESS_KEY_ID you exported above),
#    AWS_SECRET_ACCESS_KEY (= the SPACES_SECRET_ACCESS_KEY).
#    Rename backend.tf.disabled -> backend.tf.
sops secrets/terraform.sops.env
just tf-enable-backend

# 4. Migrate the local state file into the bucket. Confirm the prompt with 'yes'.
just tf-init-migrate
```

After that, the local `terraform.tfstate` becomes obsolete (terraform leaves a `*.backup`
behind -- safe to delete once you've confirmed the bucket has the real state).

Commit both `terraform/backend.tf` (now enabled) and `secrets/terraform.sops.env` (now
populated) so the next operator clones a repo that's already wired for the remote
backend.

The same Spaces access key you used to bootstrap the bucket continues to serve as the
backend's auth credential. No scoped key, no rotation dance -- if you want to rotate,
generate a new key in the DO console, update the sops file, re-deploy.

## Day-2

Every subsequent terraform command is wrapped by `sops exec-env` so the DO token + Spaces
access key get decrypted from `secrets/terraform.sops.env` into the child process's env.
You don't need to export anything yourself; just:

```bash
just tf-plan
just tf-apply
just tf-destroy
just tf-ip
```

If the sops file is missing, the recipes fall back to running terraform raw and trusting
your shell env -- useful for re-bootstrapping after a wipe.

## What the firewall opens

| Port      | Protocol | Source                | Why                                                          |
|-----------|----------|-----------------------|--------------------------------------------------------------|
| 22        | TCP      | `allowed_ssh_cidrs`   | SSH. Lock down after tailscale comes up, or remove and use `tailscale ssh`. |
| 80, 443   | TCP      | `0.0.0.0/0`           | Caddy + Let's Encrypt. Toggle off with `expose_http = false`. |
| 41641     | UDP      | `0.0.0.0/0`           | Tailscale direct peer connections (NAT traversal).            |
| ICMP      | -        | `0.0.0.0/0`           | Ping.                                                         |

Outbound is wide open.

## Destroy ordering caveat

Because the bucket holding the state is itself a resource in that state, a naive
`terraform destroy` will try to delete the bucket and then immediately fail to write the
final state update. To fully tear down:

```bash
# 1. Migrate state back to local so terraform isn't deleting its own backend mid-destroy.
just tf-disable-backend                          # renames backend.tf -> backend.tf.disabled
sops exec-env ../secrets/terraform.sops.env \
    'terraform init -migrate-state'              # copies remote state back to local
# 2. Now destroy with local state.
just tf-destroy
```

You will almost certainly never need to do this for PyTexas. Documented for completeness.

## What this does NOT manage

- DNS records (add a `digitalocean_record` block when we know hostnames)
- Reserved IPs (cost an extra $4/mo; skip unless we need stable IP across recreates)
- The **bootstrap** Spaces access key (manually generated at
  <https://cloud.digitalocean.com/spaces/access_keys>; can be revoked after step 5
  above completes if you don't need a second key for backups/etc.)

## What the firewall opens

| Port      | Protocol | Source         | Why                                                          |
|-----------|----------|----------------|--------------------------------------------------------------|
| 22        | TCP      | `allowed_ssh_cidrs` | SSH. Lock down after tailscale comes up, or remove and use `tailscale ssh`. |
| 80, 443   | TCP      | `0.0.0.0/0`    | Caddy + Let's Encrypt. Toggle off with `expose_http = false`. |
| 41641     | UDP      | `0.0.0.0/0`    | Tailscale direct peer connections (NAT traversal).            |
| ICMP      | -        | `0.0.0.0/0`    | Ping.                                                         |

Outbound is wide open.

## What this does NOT manage

- DNS records (add a `digitalocean_record` block when we know hostnames)
- Spaces / object storage
- Reserved IPs (cost an extra $4/mo; skip unless we need stable IP across recreates)

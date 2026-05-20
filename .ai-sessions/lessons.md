# Lessons Learned

## Recent
<!-- 10 most recent lessons, newest first -->
- After a mid-session restructure (renamed recipes, moved paths), grep every doc for the old names before calling it done — doc drift stays invisible until someone follows the README and hits a recipe/path that no longer exists (2026-05-20)
- gitleaks and pre-commit's `check-yaml` both need the sops-encrypted files allowlisted/excluded — they look like valid YAML/dotenv but aren't plain-parseable, and their `ENC[...]` / age blocks are not leaks (2026-05-20)
- Just's `set working-directory := ".."` cascades into recursive `just` invocations — a `default: @just --list` recipe in a nested justfile will silently load the parent's justfile instead of its own. Use `repo_root := justfile_directory() / ".."` + explicit `cd` per recipe instead. Test with bare `just`, not `just --list` (different code path) (2026-05-18)
- `temporal-ts-net` defaults its tsnet state dir to `~/.config/tsnet-<hostname>/`, NOT the volume-mounted `/var/lib/tailscale` — pass `--tailscale-state-dir=/var/lib/tailscale` explicitly or the tailnet node name drifts (`-1`, `-2`, ...) on every container recreate (2026-05-18)
- Compose `include:` puts every included service into the same project namespace — service-name collisions across files break the merge; rename your master substrate services with a project-specific prefix (e.g. `pytexas-temporal`) rather than the included services (2026-05-18)
- Just's `[no-exit-message]` recipe attribute suppresses the "Recipe failed with exit code N" tracebacks on non-zero exits — use it on user-facing recipes that may legitimately exit 1 (unknown arg, missing precondition) (2026-05-18)
- DigitalOcean `digitalocean_spaces_bucket` creation hits the S3 API (not the platform API) and requires `SPACES_ACCESS_KEY_ID` + `SPACES_SECRET_ACCESS_KEY` in addition to `TF_VAR_do_token` — generate the Spaces key manually at `https://cloud.digitalocean.com/spaces/access_keys` before the first apply (2026-05-18)
- `digitalocean_spaces_key` rejects the `fullaccess` permission when paired with a bucket-scoped grant — bucket-scoped grants can only be `read` or `readwrite`; `fullaccess` is account-wide (no bucket field) (2026-05-18)
- Multi-step bash commands that include `git commit` / `git push` / `terraform apply` need `set -euo pipefail` or `&&`-chaining — newline-separated steps don't propagate exit codes, so a failed pre-flight check ships the destructive action anyway (2026-05-18)
- `community.docker.docker_compose_v2`'s `services:` parameter doesn't actually limit which services get created — it only scopes operations on them. Use direct shell `docker compose up -d <svc>` when you need true service filtering (2026-05-18)

## Infrastructure (DigitalOcean / Terraform)

- DigitalOcean projects require exactly one default project per account; setting `is_default: false` on the only project fails — use `lifecycle { ignore_changes = [is_default] }` on the project resource (2026-05-18)
- DO auto-attaches the domain URN to the project that owns the records pointing at it — list `"do:domain:<name>"` in `digitalocean_project.resources` to keep terraform from trying to remove it on every apply (2026-05-18)
- DO Spaces does NOT support folder-level / prefix-level IAM — bucket-level access keys only. Use separate buckets for permission boundaries; bucket count is effectively free since pricing is by total storage ($5/mo for first 250GB across all buckets) (2026-05-18)
- `digitalocean_record` has no URN attribute — DNS records can't be assigned to projects directly; they're implicitly grouped via the domain URN listed in the project's resources (2026-05-18)
- `data "digitalocean_ssh_keys" "all" {}` pulls every SSH key in the account — cleaner than `digitalocean_ssh_key` with `for_each` over a variable list of names (2026-05-18)
- The terraform `do_token` variable env-var convention is `TF_VAR_do_token` — NOT the DigitalOcean provider's native `DIGITALOCEAN_TOKEN` env var. They don't bridge (2026-05-18)
- Self-referential state bucket pattern works fine for routine apply/plan; `terraform destroy` is the only awkward case (it tries to delete its own backend mid-destroy). Workaround: rename `backend.tf` → `backend.tf.disabled`, migrate state back to local, then destroy (2026-05-18)
- DO Spaces backend block in terraform requires `skip_credentials_validation`, `skip_metadata_api_check`, `skip_region_validation`, `skip_requesting_account_id`, `skip_s3_checksum`, `use_path_style` — without all of them, the S3 backend tries AWS-specific probes that fail (2026-05-18)
- Terraform's `-backend=false` flag only affects `init`; every subsequent `plan`/`apply` re-reads `backend.tf` and demands the backend be initialized — gate the backend during the chicken-and-egg bootstrap by naming the file `backend.tf.disabled` (terraform only auto-loads `*.tf`) (2026-05-18)

## Docker / Compose

- Docker Compose `include:` shares the project namespace across all included files — service-name collisions break the merge even when one is profile-gated (the profile only controls START, not whether the name is defined) (2026-05-18)
- Compose's `--remove-orphans` flag only removes containers that DON'T match any defined service — profile-gated services in the model are NOT orphans, so old containers from a prior layout (matching a now-profile-gated name) won't get cleaned up automatically (2026-05-18)
- `docker compose up <svc>` with `depends_on: temporal` will pull `temporal` into the started set even if you only named one service — use `--no-deps` to skip the chain when the dependency lives in a different compose project (2026-05-18)
- Bot/middleware repos: profile-gated `temporal` and `caddy` (for local-dev standalone) plus app services that don't `depends_on` them is the cleanest pattern for "self-contained local dev, shared-substrate production" (2026-05-18)
- Compose builds local images as `<project>-<service>` — duplicated service name vs project name gives ugly stutter (`pytexas-discord-bot-pytexas-discord-bot`). Pick distinct names from the start (2026-05-18)

## Ansible

- `community.docker.docker_compose_v2`'s `services:` doesn't filter creation; shell out to `docker compose up -d <svc>` for true control (2026-05-18)
- Fresh DO droplets run cloud-init/unattended-upgrades on first boot — `cloud-init status --wait` at the top of the bootstrap role avoids dpkg lock races on the first apply (2026-05-18)
- Set `lock_timeout: 120` on `ansible.builtin.apt` tasks to tolerate the brief lock contention even after the cloud-init wait completes (2026-05-18)
- `community.sops` collection's `lookup('community.sops.sops', path)` decrypts on the controller; pair with `ansible.builtin.copy: content: ...` to push plaintext over SSH without ever writing it to disk on the controller side (2026-05-18)
- `community.docker` ≥3.10 ships with broken `docker_compose_v2` against some compose versions; pin to ≥5.x for reliable behavior (2026-05-18)
- `include_tasks` does not propagate `tags` from the include directive to the included tasks — to allow `--tags X` to run an included task block, tag each child task individually or use `import_tasks` (2026-05-18)

## Tooling (sops, just)

- Sops `creation_rules` `path_regex` matches against the INPUT file path, not the output — when creating new encrypted files, name them with the final `.sops.env` / `.sops.yaml` suffix from the start so they match the rule (2026-05-18)
- Sops handles dotenv format ("per-value encryption, keys stay readable") when the extension is `.env`; YAML when `.yaml`; binary (whole-file) otherwise. Use `.sops.env` and `.sops.yaml` suffixes consistently (2026-05-18)
- Just's `[no-exit-message]` suppresses "Recipe failed" tracebacks; combine with explicit `echo` + `exit N` for clean UX on user errors (2026-05-18)
- Just's `set working-directory := ".."` cascades into recursive `just` invocations and silently misdirects them at the parent's justfile — use `justfile_directory() / ".."` + explicit `cd` per recipe instead (2026-05-18)
- Sops + age recipient-based encryption: any operator's age private key can decrypt; adding a new operator is `sops updatekeys` after their public key is added to `.sops.yaml`. No password to share, no rotation pain (2026-05-18)

## Tailscale / Networking

- `temporal-ts-net` defaults state dir to `~/.config/tsnet-<hostname>/` (NOT a docker-volume path) — use `--tailscale-state-dir=/var/lib/tailscale` to map state into a persisted volume so the node name doesn't drift on restarts (2026-05-18)
- Tailscale apt repo expects its keyring at `/usr/share/keyrings/tailscale-archive-keyring.gpg` (hardcoded in the `.list` file from pkgs.tailscale.com) — putting it under `/etc/apt/keyrings/` breaks signature checks (2026-05-18)
- Reusable + pre-approved + tagged Tailscale auth keys are the right pattern for servers — one key handles host registration AND container-side tsnet registration without manual approval queues (2026-05-18)
- DO cloud firewall: open UDP 41641 for Tailscale direct peer connections, otherwise traffic relays through DERP (works but slower) (2026-05-18)

## Security

- gitleaks and pre-commit's `check-yaml` both need the sops-encrypted files allowlisted/excluded — they look like valid YAML/dotenv but aren't plain-parseable, and their `ENC[...]` / age blocks are not leaks (2026-05-20)
- A sops-encrypted repo is public-safe by design; the only real exposure is an accidental plaintext commit. A gitleaks pre-commit hook + GitHub push protection cover that vector. Rotate the underlying secrets (not just the encryption key) when revoking access, since old ciphertext lives forever in git history (2026-05-20)

## Workflow

- After a mid-session restructure (renamed recipes, moved paths), grep every doc for the old names before calling it done — doc drift stays invisible until someone follows the README and hits a dead recipe/path (2026-05-20)
- `Edit` with `old_string="KEY="` on a line that's already `KEY=existingvalue` matches the prefix and CONCATENATES `newvalue + existingvalue` instead of replacing — always include the full line value in `old_string` (2026-05-18)
- Don't guess vendor console URLs — DO Spaces keys live at `/spaces/access_keys`, NOT `/account/api/tokens`; verify with WebFetch or ask before documenting (2026-05-18)
- When `Edit` reports "file modified since read", do NOT continue downstream destructive actions — re-Read first. Failing edits in `&&`-chained bash propagate fine; failing edits in newline-separated bash do NOT (2026-05-18)
- Apply the "earn its keep" test before adding moving parts at small scale — scoped Spaces keys, capture-creds recipes, diff-based idempotent retention all over-engineer at one-droplet/one-operator scale (2026-05-18)
- Self-referential terraform state bucket survives normal apply/plan; only `destroy` is awkward — document the migrate-state-back-to-local workaround once and never run into it (2026-05-18)
- Two-justfile split — bootstrap (laptop, rare, terraform/ansible) vs maintenance (droplet, frequent, docker compose) — matches the operator's mental model better than one file with verb prefixes (2026-05-18)

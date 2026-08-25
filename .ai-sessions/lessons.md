# Lessons Learned

## Recent
<!-- 10 most recent lessons, newest first -->
- sops-encrypted terraform state in git (no remote backend): a `_tf` justfile wrapper decrypts `state.sops.json` before each run and re-encrypts IN PLACE only if the plaintext changed — skipping re-encrypt on reads avoids a new sops nonce (and git churn) every `plan`; re-encrypt even on non-zero terraform exit so a partial apply's state survives. Name the encrypted file WITHOUT `.tfstate` in it (e.g. `state.sops.json`) or `*.tfstate*` gitignore swallows it. No state locking → solo/coordinated applies only (2026-08-25)
- DO Spaces is a flat $5/mo per ACCOUNT (250 GiB + 1 TiB), NOT per bucket. Moving one tfstate file off Spaces only saves the $5 if you have no other Spaces bucket — adding e.g. a public assets bucket brings the fee right back, so the savings and the assets bucket are mutually exclusive (2026-08-25)
- The DO default project CANNOT be deleted — a full `terraform destroy` fails on it ("cannot delete the default project"), and `-target` on a resource the project references pulls the project into the destroy too. Work around with `terraform state rm digitalocean_project.main` before destroy, then `import` it back after. Also: `init -migrate-state` copies but does NOT delete the old remote state object, so the source bucket stays non-empty and needs `force_destroy` (applied to STATE first, then destroy) to delete (2026-08-25)
- DO no longer enables droplet backups from the bare `backups = true` toggle — it needs a `backup_policy` block (plan/weekday/hour). Without it every apply shows a perpetual `backups false -> true` diff that never sticks; confirm real status via the API droplet `features` list (2026-08-25)
- When main is squash-merged from a scaffold PR while a follow-up branch (e.g. a rename) is still open, the follow-up's merge from main becomes add/add conflicts across every touched file (merge base drops to the initial commit). If the only divergence is the follow-up's intended change, `git checkout --ours <files>` is the correct resolution. Then check `git status` for files the merge re-added under the pre-change name (a renamed-away secrets file) and `git rm` them — a conflict-marker-only sweep misses those (2026-08-23)
- `prevent_destroy = true` on a self-referential state bucket fails at PLAN time before any resource is touched. `force_destroy = false` alone is a poor substitute — it only fires after `terraform destroy` has already torn down everything else and then chokes on the non-empty bucket, leaving a half-wrecked state (2026-05-26)
- `terraform apply -replace=<resource>` is the idiom for "give me this one resource fresh, leave everything else alone" — the dependency graph auto-updates dependents (DNS records reading the new IP, firewall ID lists, project URN lists). Use this instead of full destroy + apply for "rebuild the droplet" workflows (2026-05-26)
- When wrapping `terraform apply` with `just` recipes (apply, rebuild, etc.), mirror the `-auto-approve` flag across all variants — inconsistency surfaces as a silent hang at the "Enter a value: yes" prompt, indistinguishable from a true hang to the operator (2026-05-26)
- Ansible runs from the controller's working tree, not from any cloned-onto-target copy of the role code. Local uncommitted changes to `ansible/roles/...` "work" for the local operator but are invisible to anyone else who clones the repo — flag this whenever pushing a role fix you haven't committed (2026-05-26)
- After a mid-session restructure (renamed recipes, moved paths), grep every doc for the old names before calling it done — doc drift stays invisible until someone follows the README and hits a recipe/path that no longer exists (2026-05-20)
- gitleaks and pre-commit's `check-yaml` both need the sops-encrypted files allowlisted/excluded — they look like valid YAML/dotenv but aren't plain-parseable, and their `ENC[...]` / age blocks are not leaks (2026-05-20)

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
- `prevent_destroy = true` on a self-referential state bucket fails at PLAN time before any resource is touched. Strictly better than `force_destroy = false` alone, which only fires after destroy has torn down everything else and then chokes on the non-empty bucket. Keep both -- defense in depth (2026-05-26)
- `terraform apply -replace=<resource>` replaces one resource and lets the dependency graph auto-update dependents (DNS records, firewall droplet_ids, project resource URNs). Use this for "rebuild the droplet, keep DNS + bucket + state" instead of full destroy + apply (2026-05-26)

## Docker / Compose

- Docker Compose `include:` shares the project namespace across all included files — service-name collisions break the merge even when one is profile-gated (the profile only controls START, not whether the name is defined) (2026-05-18)
- Compose's `--remove-orphans` flag only removes containers that DON'T match any defined service — profile-gated services in the model are NOT orphans, so old containers from a prior layout (matching a now-profile-gated name) won't get cleaned up automatically (2026-05-18)
- `docker compose up <svc>` with `depends_on: temporal` will pull `temporal` into the started set even if you only named one service — use `--no-deps` to skip the chain when the dependency lives in a different compose project (2026-05-18)
- Bot/middleware repos: profile-gated `temporal` and `caddy` (for local-dev standalone) plus app services that don't `depends_on` them is the cleanest pattern for "self-contained local dev, shared-substrate production" (2026-05-18)
- Compose builds local images as `<project>-<service>` — duplicated service name vs project name gives ugly stutter (`pytexas-discord-bot-pytexas-discord-bot`). Pick distinct names from the start (2026-05-18)

## Ansible

- When refactoring a role, trace the FRESH-start path, not just the already-running one — a step that's redundant on an existing system (e.g. `/srv/pytexas` already created by a prior run) can be load-bearing on a clean bootstrap. Removing the "ensure services_root exists, owned by deploy user" task broke fresh-droplet clones (deploy user can't mkdir in root-owned `/srv`) while the running droplet kept working (2026-05-20)
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
- When wrapping `terraform apply` with `just` recipes (apply, rebuild, etc.), mirror the `-auto-approve` flag across every variant — inconsistency surfaces as a silent hang at the "Enter a value:" prompt, indistinguishable from a real hang to the operator (2026-05-26)

## Tailscale / Networking

- `temporal-ts-net` defaults state dir to `~/.config/tsnet-<hostname>/` (NOT a docker-volume path) — use `--tailscale-state-dir=/var/lib/tailscale` to map state into a persisted volume so the node name doesn't drift on restarts (2026-05-18)
- Tailscale apt repo expects its keyring at `/usr/share/keyrings/tailscale-archive-keyring.gpg` (hardcoded in the `.list` file from pkgs.tailscale.com) — putting it under `/etc/apt/keyrings/` breaks signature checks (2026-05-18)
- Reusable + pre-approved + tagged Tailscale auth keys are the right pattern for servers — one key handles host registration AND container-side tsnet registration without manual approval queues (2026-05-18)
- DO cloud firewall: open UDP 41641 for Tailscale direct peer connections, otherwise traffic relays through DERP (works but slower) (2026-05-18)

## Security

- gitleaks and pre-commit's `check-yaml` both need the sops-encrypted files allowlisted/excluded — they look like valid YAML/dotenv but aren't plain-parseable, and their `ENC[...]` / age blocks are not leaks (2026-05-20)
- A sops-encrypted repo is public-safe by design; the only real exposure is an accidental plaintext commit. A gitleaks pre-commit hook + GitHub push protection cover that vector. Rotate the underlying secrets (not just the encryption key) when revoking access, since old ciphertext lives forever in git history (2026-05-20)

## Workflow

- Ansible runs from the controller's working tree, not from any cloned-onto-target copy of the role code. Local uncommitted changes to `ansible/roles/...` "work" for the local operator but are invisible to anyone else who clones the repo. Flag explicitly whenever pushing a role fix you haven't committed — solo testing won't surface the gap (2026-05-26)
- After a mid-session restructure (renamed recipes, moved paths), grep every doc for the old names before calling it done — doc drift stays invisible until someone follows the README and hits a dead recipe/path (2026-05-20)
- `Edit` with `old_string="KEY="` on a line that's already `KEY=existingvalue` matches the prefix and CONCATENATES `newvalue + existingvalue` instead of replacing — always include the full line value in `old_string` (2026-05-18)
- Don't guess vendor console URLs — DO Spaces keys live at `/spaces/access_keys`, NOT `/account/api/tokens`; verify with WebFetch or ask before documenting (2026-05-18)
- When `Edit` reports "file modified since read", do NOT continue downstream destructive actions — re-Read first. Failing edits in `&&`-chained bash propagate fine; failing edits in newline-separated bash do NOT (2026-05-18)
- Apply the "earn its keep" test before adding moving parts at small scale — scoped Spaces keys, capture-creds recipes, diff-based idempotent retention all over-engineer at one-droplet/one-operator scale (2026-05-18)
- Self-referential terraform state bucket survives normal apply/plan; only `destroy` is awkward — document the migrate-state-back-to-local workaround once and never run into it (2026-05-18)
- Two-justfile split — bootstrap (laptop, rare, terraform/ansible) vs maintenance (droplet, frequent, docker compose) — matches the operator's mental model better than one file with verb prefixes (2026-05-18)

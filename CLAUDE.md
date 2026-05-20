# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

PyTexas Foundation infrastructure-as-code. Stands up one DigitalOcean droplet in `sfo3`,
hardened by ansible, hosting a unified docker compose project that includes the
`pretix-discord-middleware` and `pytexas-discord-bot` service repos as sub-clones. Terraform
manages the droplet, firewall, DO project, DNS records on `pytx.org`, and a Spaces bucket
that holds its own state via the self-referential bootstrap pattern.

## The architecture concept that governs everything

**Two justfiles for two operational contexts:**

- **`justfile`** at the repo root: maintenance recipes (`up`, `down`, `restart`, `logs`,
  `pull`). Meant to be invoked **on the droplet itself** after `ssh pytexas@infra.pytx.org`
  and `cd /srv/pytexas`. Direct `docker compose` calls -- no SSH out.
- **`bootstrap/justfile`**: laptop-side recipes (`apply`, `plan`, `destroy`, `ip`, `sops`,
  `rekey`, `setup`, `lint`) that drive terraform and ansible against the remote droplet.

The split reflects how often each set runs: maintenance is daily, bootstrap is rare. The
infrastructure repo is cloned to `/srv/pytexas` on the droplet, so the repo-root justfile
ends up deployed there alongside the compose stack.

When working in this repo, always know which context a change belongs to:

- "Change how a service starts" → repo-root `justfile` or `docker-compose.yml`.
- "Change how the droplet is provisioned" → `ansible/`, `bootstrap/justfile`.
- "Change what DigitalOcean resources exist" → `terraform/`, `bootstrap/justfile`.
- "Change a secret" → `bootstrap/justfile` `sops` recipe.

## Common commands

**From the laptop** (in `bootstrap/`):

```bash
just apply         # terraform + ansible end-to-end
just plan          # terraform plan, no apply
just destroy       # terraform destroy (read terraform/README.md first -- there's a backend dance)
just ip            # print the droplet's public IPv4
just sops <file>   # edit/create an encrypted secret. e.g. just sops secrets/pytexas.sops.env
just rekey         # re-encrypt every secrets file (after adding/removing an age recipient)
just setup         # install ansible collections (one-time after git clone)
just lint          # terraform fmt + validate
```

**From the droplet** (in `/srv/pytexas/`):

```bash
just up      <all|bot|middleware|temporal>
just down    <all|bot|middleware|temporal>      # 'all' removes containers; specific target stops only
just restart <all|bot|middleware|temporal>
just logs    <bot|middleware|temporal>           # no 'all' -- too much noise
just pull    <all|bot|middleware|infra>          # git pull + rebuild + restart
```

All `just <verb>` calls without a target print the unified help block.

## Non-obvious things to know

### Self-referential terraform state
The Spaces bucket that holds terraform state is itself a terraform-managed resource. The
first apply runs with local state (`backend.tf` lives as `backend.tf.disabled` so terraform
ignores it -- only `*.tf` is auto-loaded). After the bucket exists, you rename
`backend.tf.disabled` → `backend.tf` and run `terraform init -migrate-state`. From then on
state lives in Spaces. Full procedure in `terraform/README.md`. **Never `terraform destroy`
without reading the destroy ordering caveat there** -- you'd delete the bucket holding
your state mid-destroy.

### Sops + age, recipients in `.sops.yaml`
All secrets live encrypted in `secrets/` under two patterns: `*.sops.env` (dotenv format,
deployed as `.env` on the droplet) and `*.sops.yaml` (YAML format, consumed by ansible
during the play). The age private key lives at `~/.config/sops/age/keys.txt` on operator
laptops, with a backup copy in 1Password. Adding a new operator = adding their age public
key to `.sops.yaml` + running `just rekey`. Full lifecycle in `secrets/README.md`.

Sops `creation_rules` `path_regex` matches against the **input** file path -- when
creating a new encrypted file, name it with the final `.sops.env` / `.sops.yaml` suffix
from the start.

### Unified compose, one project
The master `docker-compose.yml` at the repo root pulls every service repo in via `include:`.
**One docker compose project, not three.** That's why master substrate services are named
`pytexas-temporal` and `pytexas-caddy` -- to avoid colliding with the middleware's
profile-gated `temporal` and `caddy` services (which exist in the same project's namespace
once included). The `default` network has an alias `temporal` on `pytexas-temporal` so the
middleware's `worker` and `web` can reach the master Temporal via `temporal:7233` without
knowing the prefixed name.

### Master Temporal needs `--tailscale-state-dir`
`temporal-ts-net` defaults tsnet state to `~/.config/tsnet-<hostname>/` (not the
volume-mounted `/var/lib/tailscale`). Without `--tailscale-state-dir=/var/lib/tailscale` on
the command line, every container recreate registers as a fresh tailnet node and the
hostname drifts (`pytexas-temporal-1`, `pytexas-temporal-2`, ...). The flag is set in
`docker-compose.yml`; keep it there.

### Service repos are sub-clones inside `/srv/pytexas/`
Ansible clones `pretix-discord-middleware` and `pytexas-discord-bot` into the infra repo's
checkout on the droplet. Both are gitignored at the repo root. The master compose's
`include:` paths reference them relatively.

### Compose v2 quirks
- `community.docker.docker_compose_v2`'s `services:` parameter does **not** filter which
  services get created -- only scopes operations on them. If you need true service
  filtering, shell out to `docker compose up -d <svc>`.
- Compose `--remove-orphans` won't remove containers whose names match profile-gated
  services in the model (they're "valid but not enabled," not orphans).
- `set working-directory := "..."` in a nested justfile cascades into recursive `just`
  invocations and silently misdirects them at the parent's justfile -- avoid; use
  `justfile_directory() / ".."` + explicit `cd` instead.

### DigitalOcean specifics
- Spaces bucket creation uses the S3 API, not the platform API -- needs
  `SPACES_ACCESS_KEY_ID` + `SPACES_SECRET_ACCESS_KEY` env vars in addition to
  `TF_VAR_do_token`. Generate the Spaces key at
  <https://cloud.digitalocean.com/spaces/access_keys> (a separate page from API tokens).
- `digitalocean_spaces_key` grants: `fullaccess` is account-wide only; bucket-scoped
  grants must be `read` or `readwrite`.
- DO requires exactly one default project per account; `digitalocean_project.is_default`
  is in a `lifecycle { ignore_changes }` so terraform doesn't try to flip it.
- DO auto-attaches a domain URN to whichever project owns the records under it; that's
  why `"do:domain:${var.dns_domain}"` is in the project's `resources` list.

## Subsystem-specific docs (read these when working in those areas)

- **`terraform/README.md`** -- bootstrap dance, what each resource does, destroy ordering
  caveat.
- **`ansible/README.md`** -- role order, how the inventory is generated from terraform
  output.
- **`secrets/README.md`** -- multi-operator onboarding, key rotation, lost-laptop
  recovery.

## Workflow rules in play

The user's global rules (`~/.claude/rules/`) govern collaboration on this repo:

- Test-driven mindset; smallest reasonable change.
- Trust internal code; validate at boundaries.
- All Markdown files use Mermaid for diagrams, never ASCII art.
- Git: never commit to `main` directly. Use feature branches; create PRs. Only the user
  merges to `main`. Always sign commits with `-S`. Don't skip hooks (`--no-verify`)
  unless explicitly authorized.
- BPE workflow for commits: `/bpe:session-summary` then `/bpe:commit-message` then
  `git commit -S -F commit-msg.md`. `commit-msg.md` is gitignored.
- A gitleaks pre-commit hook (`.pre-commit-config.yaml` + `.gitleaks.toml`) blocks
  accidental plaintext-secret commits. Run `pre-commit install` once after cloning.
  The sops-encrypted files are allowlisted, so their `ENC[...]` / age blocks don't trip
  it. If a hook blocks a commit, investigate — don't `--no-verify` past it.

## Accumulated lessons

`.ai-sessions/lessons.md` captures specific, actionable lessons from past sessions
(grouped by category: Infrastructure, Docker/Compose, Ansible, Tailscale, Tooling,
Workflow). Skim it when picking up work in any of those areas -- it surfaces the
non-obvious gotchas this repo has already paid for.

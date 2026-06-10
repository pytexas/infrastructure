# Session Summary: PyTexas Foundation Infrastructure Bootstrap

**Date**: 2026-05-18
**Duration**: ~12 hours (intermittent, single long session)
**Conversation Turns**: ~110
**Estimated Cost**: ~$45-60 (Opus 4.7, 521.8k context tokens)
**Model**: claude-opus-4-7 (1M context)

## Key Actions

- Designed and scaffolded the PyTexas Foundation infrastructure from scratch: one DigitalOcean droplet in `sfo3`, managed by terraform with a self-referential Spaces bucket holding its own state.
- Built the ansible playbook: bootstrap (hardened SSH, user, fail2ban, unattended-upgrades), docker (CE + compose plugin from official apt), tailscale (with `--ssh`), and a services role that clones the infrastructure repo and brings up the unified compose stack.
- Set up `sops + age` encryption for five categories of secrets: terraform creds, ansible-time vars, master substrate `.env`, middleware `.env`, bot `.env`. Wrote a full operator-lifecycle doc covering install, key generation, 1Password backup, multi-operator onboarding, key rotation, and lost-laptop recovery.
- Resolved the terraform state chicken-and-egg via the `backend.tf.disabled` rename pattern (terraform only auto-loads `.tf`). Successfully migrated state from local into the Spaces bucket.
- Force-replaced the droplet after the user added their laptop SSH key to DigitalOcean (the original droplet was created authorized for older keys only).
- Refactored from three separate compose projects into one unified project at `/srv/pytexas` using `include:`. Renamed master substrate services (`pytexas-temporal`, `pytexas-caddy`) to avoid collisions with the middleware's profile-gated standalone services.
- Set up `digitalocean_record` resources for `infra.pytx.org` (A + AAAA pointing at the droplet). Documented that the domain zone itself is managed outside terraform (no `digitalocean_domain` resource).
- Set Temporal namespace retention to 180 days via an idempotent ansible task (collapsed from an over-engineered jq+diff version to a simple "always run, Temporal treats same-value as no-op").
- Restructured the justfiles end-of-session: laptop-side `bootstrap/justfile` (apply/plan/destroy/ip/setup/lint/sops/rekey) and droplet-side top-level `justfile` (up/down/restart/logs/pull) — meant to be invoked from `/srv/pytexas` after SSH.
- Across the three repos (infrastructure, middleware, bot): committed and pushed production-ready compose changes — restart policy, PYTHONUNBUFFERED, profile-gated standalone services, network aliasing for the unified compose model. Merged tailscale + standalone-profile branches to `main` on the middleware repo (with a one-fix follow-up after a merge committed with conflict markers still in the file).
- Fixed Tailscale state-dir bug: `temporal-ts-net` writes tsnet state to `~/.config/tsnet-<hostname>/` by default, not the volume-mounted `/var/lib/tailscale`. Added `--tailscale-state-dir` flag.

## Prompt Inventory

| Prompt/Command | Action Taken | Outcome |
|---|---|---|
| "I'm looking to stand up infrastructure..." | Designed architecture; recommended one droplet, master substrate + per-service compose, sops for secrets | Plan accepted |
| "did you look at the code in middleware, discord-bot, and durable-wordle?" | Inspected each repo; surfaced collisions; revised plan with profile gating | Plan revised toward shared substrate |
| "Start with the scaffolding" | Wrote terraform/, ansible/, compose/, justfile, README | Initial scaffolding complete |
| "Install terraform... actually verify the service repos" | Ran terraform validate; verified repos via `gh`; corrected org casing pytexas vs PyTexas | Validation clean, URLs corrected |
| "Go ahead and do the refactors" | Standalone-profile branch in middleware; restart policy in bot; master compose with overrides | Local branches ready |
| Sops + 1Password discussion | Explained options (Vault OSS, 1Password Connect, ansible-vault, sops); recommended sops + age | Sops + age chosen |
| Tailscale token + DigitalOcean key + provider auth questions | Multiple bug-fix iterations: TF_VAR_do_token, SPACES creds, `data.digitalocean_ssh_keys.all`, Spaces key grant ("readwrite" not "fullaccess"), project is_default lifecycle | Each issue resolved, terraform clean |
| "go" (full bootstrap execution) | Wrote 5 sops files; terraform apply; tf-enable-backend; tf-init-migrate; ansible bringup | All 5 containers running |
| Cloud-init / Tailscale keyring / docker_compose_v2 services-filter issues | Cloud-init wait; `/usr/share/keyrings` path; shell-based `docker compose up worker web --no-deps` | Ansible converges cleanly |
| "the top level docker compose doesn't seem to turn everything off" | Refactored into one unified compose project at `/srv/pytexas` using `include:` with hardcoded paths | Single `docker compose down` brings everything down |
| "write just commands for this" | Added up/down/restart/logs recipes targeting all|bot|middleware|temporal | Recipes work + unified help |
| "I want the opposite. Bootstrap directory and a justfile for those. Top level should be maintenance." | Moved files to root, created `bootstrap/`, added `pull` recipes, updated ansible to git-clone the infra repo | Restructure complete |
| "temporal service rebooted and rejoins the tailnet... changes its name" | Identified missing `--tailscale-state-dir` flag, updated master compose | Future restarts will retain hostname |

## Efficiency Insights

**What went well:**
- Investigating before guessing: when the user asked "did you look at the code" or "verify the service repos", reading source directly and using `gh` for ground-truth on remote state caught real bugs before they shipped (org casing, env var names, depends_on chains).
- Failing forward through real deploys: rather than over-engineering safety nets, ran `just apply` repeatedly and let the playbook surface real bugs (cloud-init lock, keyring path, profile gating, etc.). Each fix landed in code, so the playbook is now hardened against all of them.
- Saving feedback memories at the time of each mistake (vendor URLs, Edit partial-match, bash set -e) — they're already in `~/.claude/projects/.../memory/` for next time.

**What could improve:**
- Initial sops bootstrap was over-engineered: scoped Spaces key resource, capture-creds recipe, complex diff-based retention task. User pushed back ("dirt simple", "complex ansible looks complex") and I had to back out each one. Should have asked "is this complexity earning its keep at our scale?" before adding it.
- Guessed at console URLs (DigitalOcean Spaces keys) and got corrected. Memory now exists but the cost was a follow-up correction round.
- Two destructive-action incidents: (1) Edit partial-match concatenated PRETIX_API_TOKEN with prior value; (2) bash script without `set -e` shipped a merge commit with conflict markers. Both required follow-up fix commits in `main`.
- Did not push the infrastructure repo's `scaffolding` branch during the session despite having authorization. Means user can't try `just pull infra` until they push manually.

**Course corrections:**
- "I don't want to vendor this in" → switched from copying compose contents into the master file to `include:` directive.
- "Lord that ansible looks complex. Is that absolutely required?" → collapsed 20-line jq-diff retention task to 8-line "always run, Temporal idempotent on no-op".
- "the top level docker compose doesn't seem to turn everything off" → flipped from three separate compose projects to one unified project.
- "These commands shouldn't be run locally" then "I want the opposite" → two complete justfile reorganizations.

## Process Improvements

- When designing infra, default to the simplest thing first and add complexity only when the user asks for it. At PyTexas's scale (1 droplet, 1 operator, low traffic), most "least-privilege" / "future-proofing" patterns add more friction than safety. Apply the "earn its keep" test before adding moving parts.
- For multi-step shell calls that include `git commit` or `git push` or `terraform apply`, always use `set -euo pipefail` or `&&`-chain. Newline-separated steps don't propagate exit codes.
- Before referencing a vendor console URL in docs, fetch the page or ask. URL guessing has a high error rate.
- When `Edit` reports failure mid-script (file changed since read), do NOT continue with subsequent commands that depend on the edit — read again and retry, or abort the script.
- Save feedback memories proactively, not just on user pushback. The bash-set-e and Edit-partial-match memories were saved after the mistakes shipped; saving them at design time would have prevented the shipped mistakes.

## Observations

- The user's git workflow rule "Only Mason merges to main" is honored by the classifier even when verbally overridden. Had to ask explicit permission for the tailscale → main merge in the middleware repo despite "you have permission to bypass". The classifier protected against a class of errors I was about to make (the conflict-marker merge being one of them).
- The user iterated heavily on the justfile structure (twice reorganized). The "right" answer turned out to be: maintenance at top level (run on droplet, run often), bootstrap nested (run from laptop, rare). This matched the user's mental model after they expressed it explicitly, not what I guessed.
- The Tailscale node-naming bug (state dir not persisted) was a perfect example of "the volume mount is correct but the binary doesn't write there". `docker volume inspect` would have caught it earlier — worth checking volumes are populated as expected during compose validation.
- Sops creation_rules `path_regex` matches the INPUT file's path, not the output's. Easy to misunderstand. Naming new encrypted files with the final `.sops.env` suffix from the start avoids the "no matching creation rule found" error.

## Suggested Skills for Next Session

- `temporal:temporal-developer` — if next steps touch Temporal workflow code (the middleware uses Temporal heavily and any iteration there would need this).
- `python:python` — if next steps modify the bot or middleware service code (Python projects with type hints and uv tooling).

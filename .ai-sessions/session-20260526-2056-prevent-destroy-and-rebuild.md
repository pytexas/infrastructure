# Session Summary: Prevent-Destroy and the Rebuild Workflow

**Date**: 2026-05-26
**Duration**: continuation of the 2026-05-18 / 2026-05-20 work; ~1.5 hours active this segment
**Conversation Turns**: ~15 (this segment)
**Estimated Cost**: ~$8-12 (Opus 4.7, ~530k context tokens carried forward)
**Model**: claude-opus-4-7 (1M context)

## Key Actions

- Discussed whether to do a full teardown-and-rebuild end-to-end test. Surfaced the
  prerequisites instead of jumping into it: the docs/gitleaks follow-up was pushed but
  `main` was still at the initial commit, the infra repo had been made public, and the
  `/srv/pytexas` fix was still uncommitted.
- Caught a latent bug while preparing: the services-role restructure had dropped the
  "ensure services_root exists owned by deploy user" task. Worked on the existing
  droplet (because `/srv/pytexas` already existed from prior runs) but would fail on a
  truly fresh droplet because the `pytexas` user can't `mkdir` inside root-owned `/srv`.
  Restored the explicit create-and-chown step before the clone.
- Pushed back on the user's instinct to "remove or comment out the bucket from
  terraform" -- that'd make terraform plan to destroy it. The right lever is
  `prevent_destroy = true` (fails at plan time, before anything is touched), paired
  with `force_destroy = false` (already there) as defense in depth.
- Added a `just rebuild` recipe that does `terraform apply -replace=
  digitalocean_droplet.main -auto-approve`. The dependency graph picks up the new
  droplet's IPs and auto-updates the DNS records, firewall, and project in the same
  plan. State bucket is never in the destroy set.
- Fixed `just rebuild` after the user hit a hang -- initial version omitted
  `-auto-approve`, so it sat at terraform's interactive confirmation prompt.
- Updated `terraform/README.md`: replaced "Destroy ordering caveat" with "Rebuilding
  vs. destroying", documenting the daily rebuild path and the rare full-teardown path
  (now requiring conscious removal of the `prevent_destroy` guard).
- Diagnosed the failed first ansible re-run: ansible's
  `infrastructure_repo_ref: main`, but `origin/main` was still at the initial commit.
  All the code was on `origin/scaffolding`. Pointed user at two unblock options.
  They flipped the ref to `scaffolding` and re-ran successfully.
- Confirmed (from the deployed code on `origin/scaffolding`) that the
  `--tailscale-state-dir` flag IS in the shipped `docker-compose.yml`, so tsnet state
  now persists in the `temporal_tsstate` volume across container recreates. Retention
  task ran from the controller's ansible code and set the default namespace to 180d.
- Generated the commit message for the pending follow-up work (the `/srv/pytexas` fix,
  `prevent_destroy`, `rebuild` recipe, README updates, and the refactor-fresh-start
  lesson in `lessons.md`).

## Prompt Inventory

| Prompt/Command | Action Taken | Outcome |
|---|---|---|
| "can I run start-to-finish and delete all DO infra and test again?" | Audited the fresh-start path; found `/srv/pytexas` perm bug; fixed in services role | Bug fixed in working tree; flagged prerequisites |
| "I did the commit and push, verify everything is there" | Checked `origin/main` vs `origin/scaffolding`, git status, gh visibility | Found: fix uncommitted, main empty, repo public |
| "what is point 3?" | Re-explained the self-referential destroy + migrate-state-back-to-local | User understood |
| "How can we set up the bucket to not be destroyed?" | Added `prevent_destroy = true`, explained why commenting out resource is wrong | Bucket protected at plan time |
| "Just rebuild doesn't exit" | Added `-auto-approve` to the recipe | Hang fixed |
| "does rebuild update DNS?" | Explained the dependency-graph auto-update for A/AAAA/firewall/project | Confirmed yes |
| "does rebuild kick off ansible?" | Answered no; offered to chain it | User decided not to chain |
| "does just apply turn backups on?" | Verified `var.enable_backups` default is true | Confirmed |
| (ansible failed output pasted) | Diagnosed: `main` empty, ansible cloned wrong ref | Provided two fix paths |
| "did this set retention + tsnet state?" | Reasoned from the shipped code on origin/scaffolding | Confirmed yes for both |
| `/bpe:commit-message` | Wrote commit-msg.md for the pending follow-up | Ready for user to commit |

## Efficiency Insights

**What went well:**
- Caught the `/srv/pytexas` perm bug *before* the user ran a full teardown — would have
  been a much worse failure mode to hit during a clean rebuild.
- Pushed back on "comment out the bucket resource" before doing anything destructive.
  The user's instinct was reasonable but would have caused terraform to plan to destroy
  the bucket — exactly the failure mode they were trying to prevent.
- After the failed ansible run, diagnosed by inspecting `origin/main` vs
  `origin/scaffolding` content directly rather than asking the user to investigate.

**What could improve:**
- Shipped `just rebuild` without `-auto-approve`, inconsistent with `just apply` which
  has it. Should have noticed the inconsistency when writing the recipe.
- Didn't catch the `infrastructure_repo_ref: main` vs `origin/main: empty` mismatch
  proactively. The "before you teardown, here's what's missing" checklist mentioned the
  branch issue but didn't STRONGLY enough flag that `main` would clone an empty repo.
  Could have suggested flipping the ref or asking the user to merge before they tried.
- Forgot to commit the `/srv/pytexas` fix before the user re-ran apply -- it worked only
  because ansible runs from the controller's working tree, not from the cloned droplet
  repo. A different operator wouldn't have the fix.

**Course corrections:**
- "Should we remove the bucket from terraform?" → "No; `prevent_destroy = true` instead."
- "Just rebuild doesn't exit" → added `-auto-approve` to match `apply`.
- "Bring up the unified stack failed" → diagnosed ref mismatch, user flipped ref.

## Process Improvements

- When wrapping `terraform apply` with `just`, mirror the auto-approve choice across all
  variants. Inconsistency surfaces as a hang and is easy to miss in review.
- When recommending a "test the bootstrap" workflow, *explicitly* check the branch
  ansible will clone matches the branch the latest code is on -- the failure mode is
  silent (ansible clones successfully, into a near-empty repo, fails on a downstream
  task with a confusing "no docker-compose.yml" error).
- Ansible's "the playbook runs from the controller" property is a double-edged sword:
  it lets local-only changes "work" without commits, but it hides commit-needed bugs
  from solo testing. Worth flagging proactively whenever pushing fixes to ansible roles.

## Observations

- The state bucket is protected by THREE different mechanisms now: `acl = private`,
  `versioning enabled`, `force_destroy = false`, AND `prevent_destroy = true`. Each
  catches a different scenario; they don't replace each other.
- `terraform apply -replace=<resource>` is genuinely the right idiom for "give me this
  one resource fresh, leave everything else alone". Should be the default mental model
  for droplet rebuilds, not `terraform destroy` + `terraform apply`.
- The infra repo's branch hygiene (everything on `scaffolding`, `main` empty) made for
  a real footgun during the first re-test attempt. After this commit lands, the user
  should merge `scaffolding` → `main` so the default ref points at something real.

## Suggested Skills for Next Session

- `temporal:temporal-developer` — if next steps touch the middleware's Temporal worker
  or workflow code.
- `python:python` — if next steps touch the bot or middleware service code.

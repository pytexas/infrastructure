# secrets/

`sops`-encrypted dotenv files. Plaintext only ever exists in `$EDITOR` while you're
editing or in transit during an `ansible-playbook` run. The ciphertext is safe to commit
to a public repo.

## How multi-operator access works

`sops` uses **recipient-based encryption**. The `.sops.yaml` file at the repo root lists
one `age` public key per operator under the `creation_rules` block. When sops encrypts a
file, it encrypts the data key once **per recipient**, so any one of them can decrypt
with their corresponding private key.

```mermaid
flowchart LR
    plain[plaintext .env] --> sops_e[sops -e]
    sops_e --> cipher[secrets/foo.sops.env]
    cipher -.->|encrypted to mason's pubkey| dec_m[mason's<br/>age private key]
    cipher -.->|encrypted to alice's pubkey| dec_a[alice's<br/>age private key]
    cipher -.->|encrypted to bob's pubkey| dec_b[bob's<br/>age private key]
    dec_m --> plain_m[plaintext]
    dec_a --> plain_a[plaintext]
    dec_b --> plain_b[plaintext]
```

Recipients are **OR**ed, not ANDed -- any single operator with a private key matching one
of the listed public keys can decrypt. Adding an operator does not require anyone else's
involvement at decrypt time; it only requires an existing operator to re-encrypt the
files **once**, after the new public key is added to `.sops.yaml`.

The age **public** keys are safe to commit. The age **private** keys never leave
operator laptops (with a copy stored in each operator's 1Password vault as a backup).

## First-time setup (per operator)

Every operator runs this once, on their laptop.

### 1. Install `sops` and `age`

**Ubuntu / Debian:**

```bash
sudo apt update && sudo apt install -y age

curl -fsSL https://github.com/getsops/sops/releases/latest/download/sops-v3.13.1.linux.amd64 \
  -o /tmp/sops
sudo install -m 0755 /tmp/sops /usr/local/bin/sops
rm /tmp/sops
```

**macOS (Homebrew):**

```bash
brew install age sops
```

Verify:

```bash
age --version
sops --version | head -1
```

If a newer `sops` release exists when you're reading this, bump the URL. Check
<https://github.com/getsops/sops/releases/latest> for the current version.

### 2. Generate your age keypair

```bash
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
chmod 600 ~/.config/sops/age/keys.txt
```

The file contains both halves of the keypair:

```
# created: 2026-05-18T15:30:00-05:00
# public key: age1qyqszq...yourkey
AGE-SECRET-KEY-1ABCXYZ...
```

### 3. Back up the private key to 1Password

This is your only recovery if your laptop dies or your disk gets wiped.

1. Open 1Password and create a new **Secure Note** in your personal vault.
2. Title: `sops age key — <your-name> <hostname>`.
3. Tag: `sops`.
4. Body: paste the **entire contents** of `~/.config/sops/age/keys.txt` (both the
   `# public key:` comment line and the `AGE-SECRET-KEY-...` line).

If your laptop is later compromised or lost, you'll restore by pasting this file back to
`~/.config/sops/age/keys.txt` on a new machine. (See [Recovery](#recovery--lost-laptop)
below.)

### 4. Hand off your public key

Open your keys.txt:

```bash
grep '^# public key:' ~/.config/sops/age/keys.txt
```

Send **only the `age1...` value** (not the secret key, not the full line) to an existing
operator via a PR against `.sops.yaml` -- see [Adding a new operator](#adding-a-new-operator)
below for the operator-side flow.

### 5. Verify

After an existing operator has merged your public key and rekeyed the files (see below),
clone this repo and confirm you can decrypt every file with your local key:

```bash
for f in secrets/*.sops.env secrets/*.sops.yaml; do
    sops -d "$f" >/dev/null && echo "OK   $f" || echo "FAIL $f"
done
```

Every file should report `OK`. If anything reports `FAIL`, the rekey hasn't propagated
yet -- the operator needs to commit the result of `just rekey`.

## Files in this directory

Two flavors of file: **dotenv** files end in `.sops.env` and get decrypted into `.env`
files on the droplet, where containers consume them. **YAML** files end in `.sops.yaml`
and are loaded by ansible itself on the controller -- they never cross to the droplet.

| File                                       | Format     | Consumed by                                  | Decrypts to (on droplet)                                       |
|--------------------------------------------|------------|----------------------------------------------|----------------------------------------------------------------|
| `terraform.sops.env`                       | dotenv     | terraform (via `sops exec-env` in justfile)  | -- never leaves your laptop --                                 |
| `ansible.sops.yaml`                        | YAML vars  | ansible (controller-side, `load_vars`)       | -- never leaves your laptop --                                 |
| `pytexas.sops.env`                         | dotenv     | Master compose (Temporal + Caddy)            | `/srv/pytexas/.env`                                            |
| `dispatch.sops.env`                        | dotenv     | middleware web + worker containers           | `/srv/pytexas/dispatch/.env`                                   |
| `pytexas-discord-bot.sops.env`             | dotenv     | discord bot container                        | `/srv/pytexas/pytexas-discord-bot/.env`                        |

## Editing

Run the `just` recipes from `bootstrap/` (or use raw `sops` from anywhere).

```bash
# Create or edit (opens $EDITOR with plaintext; re-encrypts on save)
cd bootstrap && just sops secrets/pytexas.sops.env
# or, raw:
sops secrets/pytexas.sops.env

# Read-only peek
sops -d secrets/pytexas.sops.env

# Sanity-check that you can decrypt every file with your local key
for f in secrets/*.sops.env secrets/*.sops.yaml; do
    sops -d "$f" >/dev/null && echo "OK   $f" || echo "FAIL $f"
done
```

## Variable reference

The exact set of variables each service needs lives in that service's repo. Treat the
following as starting points -- check the service's README or source for the full list
before deploying.

### `terraform.sops.env`

Credentials terraform needs to talk to DigitalOcean (the platform API for droplets/DNS,
plus the Spaces S3-compatible API for the public assets bucket). The `bootstrap/justfile`
terraform recipes wrap terraform with `sops exec-env` on this file, so the values are
decrypted in memory and exported only for the terraform child process. State is not remote;
it lives sops-encrypted at `terraform/state.sops.json`, so no backend/AWS_* credentials.

```dotenv
# DigitalOcean platform API token -- read/write. Generate at
# https://cloud.digitalocean.com/account/api/tokens
TF_VAR_do_token=dop_v1_REPLACE_ME

# Spaces access key -- generated manually at
# https://cloud.digitalocean.com/spaces/access_keys. The DO provider reads the
# SPACES_* names to create/manage the assets bucket; the same key writes assets.
SPACES_ACCESS_KEY_ID=REPLACE_ME
SPACES_SECRET_ACCESS_KEY=REPLACE_ME
```

### `ansible.sops.yaml`

Controller-side vars consumed by the playbook itself. Loaded via `community.sops.load_vars`
in `playbook.yml`'s `pre_tasks`. These never reach the droplet.

```yaml
# Tailscale auth key for joining the droplet host to the tailnet. Use the same key here
# and in pytexas.sops.env (as TS_AUTHKEY) -- one reusable, pre-approved, tagged key
# registers both the host and the Temporal container as separate tailnet nodes. Best
# practice: create the key with tag:pytexas in https://login.tailscale.com/admin/settings/keys
# so the registered devices show up under that tag in your ACLs.
tailscale_auth_key: tskey-auth-REPLACE_ME
```

The `TAILSCALE_AUTH_KEY` env var is still honored as a fallback (in `group_vars/all.yml`)
if this file is absent, so first-time bootstrap can work before sops is set up. Once
this file exists, its value takes precedence.

### `pytexas.sops.env`

```dotenv
# Tailscale hostname the master Temporal dev server registers as on the tailnet.
TS_HOSTNAME=pytexas-temporal

# Tailscale auth key for the Temporal container (same value as `tailscale_auth_key`
# in ansible.sops.yaml -- one reusable, pre-approved, tagged key serves both the
# droplet host and the Temporal container).
TS_AUTHKEY=tskey-auth-REPLACE_ME

# Public hostname for the dispatch web service (used by master Caddy).
MIDDLEWARE_DOMAIN=middleware.pytexas.org
```

### `dispatch.sops.env`

Service-specific config -- Discord webhook/bot tokens, Pretix API key, etc. See
<https://github.com/pytexas/dispatch> for the authoritative list.

### `pytexas-discord-bot.sops.env`

Discord bot token and any other bot-specific config. See
<https://github.com/pytexas/pytexas-discord-bot>.

## Adding a new operator

When someone else needs to be able to decrypt and deploy:

1. **They** complete [First-time setup](#first-time-setup-per-operator) on their laptop
   and send you their `age1...` public key (e.g. via PR against `.sops.yaml` or any
   secure channel -- the public key itself isn't sensitive).
2. **You** edit `.sops.yaml` and add their public key under the existing `age:` list
   with a comment naming them:

   ```yaml
   creation_rules:
     - path_regex: ^secrets/.*\.sops\.env$
       key_groups:
         - age:
             # mason -- laptop
             - age17u5zkzgr4ca49sl9n42zk6aruq8d5xntnuxkhyjwvku80tx93afqm7a0fz
             # alice -- laptop
             - age1qyqszq...newkey
   ```

3. **You** re-encrypt every existing secrets file with the new recipient list:

   ```bash
   cd bootstrap && just rekey
   # equivalent to: sops updatekeys secrets/*.sops.env secrets/*.sops.yaml
   ```

   This does **not** change the underlying plaintext; it adds a new encrypted copy of
   the data key for the new recipient. Existing recipients can still decrypt.

4. **You** commit both `.sops.yaml` and the modified `secrets/*.sops.env` files in one
   PR. Once merged, the new operator can `git pull` and immediately decrypt.

## Removing an operator

When someone leaves or their key is compromised:

1. Remove their `age1...` line from `.sops.yaml`.
2. Run `cd bootstrap && just rekey`. New encrypted copies of the data keys are written
   **without** the removed recipient.
3. Commit `.sops.yaml` and the re-encrypted files.

**Important caveat:** the historical git commits still contain ciphertext that the
removed recipient's old private key can decrypt. Removing them from `.sops.yaml` only
prevents *future* re-encrypts from including them. If their access truly needs to be
revoked, you must also **rotate the underlying secrets** (Tailscale keys, API tokens,
Discord tokens) so the plaintext they once had access to is no longer valid.

## Recovery -- lost laptop

If you lose access to your private key (laptop died, disk wiped, etc):

1. On the replacement machine, install `sops` and `age` ([step 1 above](#1-install-sops-and-age)).
2. Open 1Password, find your `sops age key` secure note, copy its contents.
3. Restore the keypair file:

   ```bash
   mkdir -p ~/.config/sops/age
   # Paste the 1Password contents into ~/.config/sops/age/keys.txt
   chmod 600 ~/.config/sops/age/keys.txt
   ```

4. Verify:

   ```bash
   for f in secrets/*.sops.env secrets/*.sops.yaml; do
       sops -d "$f" >/dev/null && echo "OK   $f" || echo "FAIL $f"
   done
   ```

If the laptop itself was compromised (theft, malware), don't just restore the same key
-- generate a fresh one and follow [Adding a new operator](#adding-a-new-operator) with
the new public key, then [Removing an operator](#removing-an-operator) for the old one.
Then **rotate the underlying secrets** since the old key may have already exfiltrated
plaintext.

## Rotation

- **Rotate the underlying secret** (Tailscale auth key, Discord token, API key) any time
  you suspect leakage, when an operator leaves, or on a schedule. Edit the relevant file
  (`cd bootstrap && just sops secrets/<file>`), then `just apply` to re-push the decrypted
  `.env` and restart affected containers. To push secrets only (no full playbook):
  `cd ansible && ansible-playbook -i inventory.local.yml playbook.yml --tags secrets`.
- **Rotate an age key** if a laptop is compromised. See [Recovery](#recovery--lost-laptop).

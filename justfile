# ABOUTME: Maintenance recipes for the PyTexas droplet. Lives at the repo root
# and is also deployed (via the repo clone) to /srv/pytexas/justfile on the
# droplet, so `ssh pytexas@infra.pytx.org && cd /srv/pytexas && just up bot`
# works in-place. Direct `docker compose` calls -- no SSH.
#
# For laptop-side bootstrap recipes (terraform, ansible, sops), see bootstrap/justfile.

default:
    @just --list

# === Service control ========================================================

# Bring up services. `just up` shows help.
[no-exit-message]
up target="":
    @just _dispatch up "{{target}}"

# Stop services. `just down all` removes containers + network; a single target
# stops just that service's container (faster to bring back up).
[no-exit-message]
down target="":
    @just _dispatch down "{{target}}"

# Restart services.
[no-exit-message]
restart target="":
    @just _dispatch restart "{{target}}"

# Tail logs of one service. No 'all' target -- too much noise.
[no-exit-message]
logs target="":
    @just _dispatch logs "{{target}}"

# git pull + rebuild + restart. Targets: all | bot | middleware | infra.
[no-exit-message]
pull target="":
    @just _dispatch pull "{{target}}"

# === Internal dispatch (shared help + verb implementations) ================

[no-exit-message]
_dispatch verb target:
    #!/usr/bin/env bash
    set -euo pipefail

    show_help() {
        cat <<'HELP'
    Service control. Run from /srv/pytexas on the droplet.

      just up      <target>    bring up        (target=all: everything)
      just down    <target>    stop            (target=all: removes containers + network)
      just restart <target>    restart
      just logs    <target>    tail logs of one service
      just pull    <target>    git pull + rebuild + restart

    Targets:
      up/down/restart    all | bot | middleware | temporal
      logs               bot | middleware | temporal       (no 'all')
      pull               all | bot | middleware | infra    ('infra' = this repo)
    HELP
    }

    if [ -z "{{target}}" ]; then
        show_help
        exit 0
    fi

    services_root="${SERVICES_ROOT:-/srv/pytexas}"

    # --- pull: git + rebuild ----------------------------------------------
    if [ "{{verb}}" = "pull" ]; then
        case "{{target}}" in
            all)
                (cd "$services_root/pretix-discord-middleware" && git pull --ff-only)
                (cd "$services_root/pytexas-discord-bot"        && git pull --ff-only)
                (cd "$services_root"                            && git pull --ff-only)
                (cd "$services_root" && docker compose up -d --build)
                ;;
            bot)
                (cd "$services_root/pytexas-discord-bot" && git pull --ff-only)
                (cd "$services_root" && docker compose up -d --build pytexbot)
                ;;
            middleware)
                (cd "$services_root/pretix-discord-middleware" && git pull --ff-only)
                (cd "$services_root" && docker compose up -d --build worker web)
                ;;
            infra)
                (cd "$services_root" && git pull --ff-only)
                (cd "$services_root" && docker compose up -d --build)
                ;;
            *)
                echo "Unknown pull target: {{target}}"
                echo
                show_help
                exit 1
                ;;
        esac
        exit 0
    fi

    # --- logs: no 'all' ---------------------------------------------------
    if [ "{{verb}}" = "logs" ] && [ "{{target}}" = "all" ]; then
        echo "'just logs all' is not supported -- pick a specific service."
        echo
        show_help
        exit 1
    fi

    # --- up/down/restart/logs: map target to compose service names --------
    case "{{target}}" in
        all)         services="" ;;
        bot)         services="pytexbot" ;;
        middleware)  services="worker web" ;;
        temporal)    services="pytexas-temporal" ;;
        *)
            echo "Unknown target: {{target}}"
            echo
            show_help
            exit 1
            ;;
    esac

    cd "$services_root"
    case "{{verb}}" in
        up)
            docker compose up -d $services
            ;;
        down)
            if [ -z "$services" ]; then
                docker compose down
            else
                docker compose stop $services
            fi
            ;;
        restart)
            docker compose restart $services
            ;;
        logs)
            docker compose logs -f --tail=100 $services
            ;;
    esac

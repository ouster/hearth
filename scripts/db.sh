#!/bin/bash
# Postgres for LiteLLM virtual keys, spend caps and store_model_in_db, under Podman.
# No Docker Desktop, no compose dependency — plain podman run.
#
#   scripts/db.sh up | down | status | logs | psql | destroy
#
# Bound to 127.0.0.1:5433 deliberately: the LAN reaches the gateway, never the DB.
# Port 5433 rather than 5432 so it cannot collide with any other Postgres.

set -euo pipefail

IMAGE=docker.io/library/postgres:16-alpine
PORT=5433

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENVF="${ROOT}/litellm/.env"
. "${ROOT}/scripts/lib.sh"
ai_load_env "$ROOT"

# Prefer an existing ai-stack-* container/volume so rename does not orphan data.
NAME="$(ai_container postgres)"
VOLUME="$(ai_volume pgdata)"

# Diagnose properly. "set POSTGRES_PASSWORD in litellm/.env" is unhelpful when
# the real problem is that the file does not exist at all.
check_env() {
  if [ ! -f "$ENVF" ]; then
    cat <<EOF
litellm/.env does not exist.

  cd ${ROOT}
  cp litellm/.env.example litellm/.env

Then set a real password:

  PW=\$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)
  sed -i '' "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=\${PW}|" litellm/.env
  sed -i '' "s|^DATABASE_URL=.*|DATABASE_URL=postgresql://litellm:\${PW}@127.0.0.1:5433/litellm|" litellm/.env
EOF
    exit 1
  fi

  if [ -z "${POSTGRES_PASSWORD:-}" ]; then
    echo "POSTGRES_PASSWORD is not set in ${ENVF}"
    echo "Present keys in that file:"
    grep -oE '^[[:space:]]*(export[[:space:]]+)?[A-Z_]+' "$ENVF" | sed 's/^/  /' || echo "  (none)"
    exit 1
  fi

  if [ "$POSTGRES_PASSWORD" = "CHANGEME" ]; then
    echo "POSTGRES_PASSWORD is still the placeholder CHANGEME in ${ENVF}"
    exit 1
  fi
}

need_machine() {
  if ! podman info >/dev/null 2>&1; then
    echo "Podman VM not running. Starting..."
    podman machine start 2>/dev/null || {
      cat <<'EOF'

No Podman machine yet. First-time setup:

  brew install podman
  podman machine init --cpus 2 --memory 2048 --disk-size 20
  podman machine start

EOF
      exit 1
    }
  fi
}

case "${1:-status}" in
  up)
    check_env
    need_machine

    podman volume exists "$VOLUME" 2>/dev/null || podman volume create "$VOLUME" >/dev/null

    if podman container exists "$NAME" 2>/dev/null; then
      podman start "$NAME" >/dev/null
      echo "started existing container ${NAME}"
    else
      podman run -d \
        --name "$NAME" \
        --restart unless-stopped \
        -p "127.0.0.1:${PORT}:5432" \
        -e POSTGRES_USER=litellm \
        -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        -e POSTGRES_DB=litellm \
        -v "${VOLUME}:/var/lib/postgresql/data" \
        --health-cmd "pg_isready -U litellm -d litellm" \
        --health-interval 10s \
        "$IMAGE" >/dev/null
      echo "created ${NAME}"
    fi

    printf 'waiting for ready'
    for _ in $(seq 1 30); do
      if podman exec "$NAME" pg_isready -U litellm -d litellm >/dev/null 2>&1; then
        echo " — ok on 127.0.0.1:${PORT}"
        echo
        echo "Next: uncomment database_url and store_model_in_db in litellm/config.yaml,"
        echo "add DATABASE_URL to ~/.config/litellm/env, then scripts/deploy.sh"
        exit 0
      fi
      printf '.'; sleep 1
    done
    echo " — TIMED OUT. Check: scripts/db.sh logs"
    exit 1
    ;;

  down)
    podman stop "$NAME" >/dev/null && echo "stopped ${NAME}"
    ;;

  status)
    podman ps -a --filter "name=${NAME}" \
      --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null \
      || echo "podman not available"
    ;;

  migrate)
    # Create LiteLLM's ~20 tables from its schema.prisma.
    #
    # LiteLLM is meant to migrate at startup, but on a pip/pipx install it
    # frequently does not — you get a healthy gateway that 500s with
    # "table public.LiteLLM_VerificationToken does not exist" the moment
    # anything touches a virtual key.
    #
    # `db push` rather than `migrate deploy`: this is a fresh database with no
    # migration history, and push syncs the schema directly. The data-loss
    # warning it prints is irrelevant on an empty database, but it is a real
    # warning on a populated one — do not run this casually later.
    VENV="${LITELLM_VENV:-$HOME/.local/pipx/venvs/litellm}"
    PY="${VENV}/bin/python"
    [ -x "$PY" ] || { echo "no litellm venv python at ${PY}"; exit 1; }
    : "${DATABASE_URL:?DATABASE_URL not set — needs to be in ~/.config/litellm/env}"

    SCHEMA=$("$PY" -c 'import pathlib,litellm.proxy;print(pathlib.Path(litellm.proxy.__file__).parent/"schema.prisma")')
    [ -f "$SCHEMA" ] || { echo "schema.prisma not found at ${SCHEMA}"; exit 1; }

    before=$(podman exec "$NAME" psql -U litellm -d litellm -tAc \
      "select count(*) from information_schema.tables where table_schema='public'" 2>/dev/null || echo "?")
    echo "tables before: ${before}"

    export PATH="${VENV}/bin:${PATH}"
    "$PY" -m prisma db push --schema "$SCHEMA" --accept-data-loss

    after=$(podman exec "$NAME" psql -U litellm -d litellm -tAc \
      "select count(*) from information_schema.tables where table_schema='public'" 2>/dev/null || echo "?")
    echo "tables after:  ${after}"

    if podman exec "$NAME" psql -U litellm -d litellm -tAc \
      "select to_regclass('public.\"LiteLLM_VerificationToken\"')" 2>/dev/null | grep -q .; then
      echo "OK — LiteLLM_VerificationToken exists."
      echo
      echo "RESTART THE GATEWAY NOW:"
      echo "  launchctl kickstart -k $(ai_litellm_agent)"
      echo
      echo "A gateway that started before the schema existed comes up with an"
      echo "uninitialised router — every role reports 'no healthy deployments'"
      echo "even though the config is correct. Restart, then create-keys.sh."
    else
      echo "FAILED — the key table still does not exist."
      exit 1
    fi
    ;;

  logs) podman logs -f "$NAME" ;;
  psql) podman exec -it "$NAME" psql -U litellm -d litellm ;;

  destroy)
    echo "This DESTROYS all virtual keys and spend history."
    read -r -p "Type the word destroy to confirm: " c
    [ "$c" = "destroy" ] || { echo "aborted"; exit 1; }
    podman rm -f "$NAME" >/dev/null 2>&1 || true
    podman volume rm "$VOLUME" >/dev/null 2>&1 || true
    echo "gone"
    ;;

  *) echo "usage: $0 {up|migrate|down|status|logs|psql|destroy}"; exit 1 ;;
esac

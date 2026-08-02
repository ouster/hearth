#!/bin/bash
# LiteLLM needs prisma ONLY in database mode. Adding database_url to config.yaml
# therefore introduces a dependency the working install never had — which is
# exactly how the first deploy failed.
#
#   scripts/setup-prisma.sh
#
# Two steps, and the second is the one people miss: installing the package is
# not enough, the client has to be generated from litellm's schema.prisma.

set -euo pipefail

VENV="${LITELLM_VENV:-$HOME/.local/pipx/venvs/litellm}"
PY="${VENV}/bin/python"

[ -x "$PY" ] || { echo "No litellm venv python at ${PY}"; exit 1; }
echo "venv: ${VENV}"

# `prisma generate` shells out to the prisma-client-py console script, which
# pipx installs into the venv's bin — not onto your PATH. Without this the
# generate step dies with "prisma-client-py: command not found".
export PATH="${VENV}/bin:${PATH}"

# ---------------------------------------------------------------- 1. package
if "$PY" -c 'import prisma' 2>/dev/null; then
  echo "  prisma package already present"
else
  echo "  installing prisma + psycopg2-binary into the litellm venv"
  if command -v pipx >/dev/null 2>&1; then
    pipx inject litellm prisma psycopg2-binary
  else
    "${VENV}/bin/pip" install prisma psycopg2-binary
  fi
fi

# ---------------------------------------------------------------- 2. generate
SCHEMA=$("$PY" - <<'PY'
import pathlib, litellm.proxy
print(pathlib.Path(litellm.proxy.__file__).parent / "schema.prisma")
PY
)

if [ ! -f "$SCHEMA" ]; then
  echo "  could not find schema.prisma (looked at ${SCHEMA})"; exit 1
fi
echo "  schema: ${SCHEMA}"

if "$PY" -c 'from prisma import Prisma' 2>/dev/null; then
  echo "  prisma client already generated"
else
  echo "  generating prisma client (downloads a query engine on first run)"
  "$PY" -m prisma generate --schema "$SCHEMA"
fi

# ---------------------------------------------------------------- verify
echo
if "$PY" -c 'from prisma import Prisma' 2>/dev/null; then
  echo "OK — litellm can now start in database mode"
  echo "Next: scripts/preflight.sh && scripts/deploy.sh"
else
  echo "FAILED — 'from prisma import Prisma' still does not work."
  echo "Try manually:"
  echo "  PATH=\"${VENV}/bin:\$PATH\" ${PY} -m prisma generate --schema ${SCHEMA}"
  echo
  echo "If it reports 'prisma-client-py: command not found', the console script"
  echo "is missing from ${VENV}/bin — reinstall with:"
  echo "  ${VENV}/bin/pip install --force-reinstall prisma"
  exit 1
fi

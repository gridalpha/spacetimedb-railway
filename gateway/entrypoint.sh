#!/bin/sh
# Caddy launcher for the SpacetimeDB public gateway.
set -eu

log() { printf '[gateway] %s\n' "$*"; }

# A `${{spacetimedb.PRIVATE_URL}}` reference renders empty until that service
# owns a deployment, so repair the value on its shape rather than trusting it.
case "${STDB_UPSTREAM:-}" in
  ''|http://:*|https://:*|:*)
    STDB_UPSTREAM="http://spacetimedb.railway.internal:3000"
    log "upstream reference was empty; defaulting to $STDB_UPSTREAM"
    ;;
esac
export STDB_UPSTREAM

if [ -z "${STDB_ADMIN_PATH:-}" ]; then
  echo "[gateway] FATAL: STDB_ADMIN_PATH is unset. Without it the admin tunnel" >&2
  echo "[gateway]        would be published at a guessable path." >&2
  exit 1
fi
# A leading slash would produce a double slash in the Caddy path matcher.
STDB_ADMIN_PATH="${STDB_ADMIN_PATH#/}"
STDB_ADMIN_PATH="${STDB_ADMIN_PATH%/}"
export STDB_ADMIN_PATH

# Compose the optional public-route regex. `^$` matches nothing, because every
# request path begins with a slash.
ROUTES="^\$"
if [ "${STDB_PUBLIC_HTTP_CALL:-false}" = "true" ]; then
  ROUTES="$ROUTES|^/v1/database/[^/]+/call/[^/]+\$"
  log "publishing the HTTP reducer-call route anonymously"
fi
if [ "${STDB_PUBLIC_HTTP_SQL:-false}" = "true" ]; then
  ROUTES="$ROUTES|^/v1/database/[^/]+/sql\$"
  log "publishing the HTTP SQL route anonymously"
fi
STDB_PUBLIC_ROUTES="$ROUTES"
export STDB_PUBLIC_ROUTES

log "listening on :${PORT:-8080}, proxying to ${STDB_UPSTREAM}"

caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile

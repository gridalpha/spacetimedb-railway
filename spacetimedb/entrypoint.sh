#!/usr/bin/env bash
# SpacetimeDB standalone launcher for Railway.
#
# Railway mounts the volume root-owned while the upstream image runs as the
# unprivileged `spacetime` user, so this script prepares the volume as root and
# drops back before exec'ing the server. It also sizes the page pool from the
# cgroup rather than the host, because Railway hosts report 48 cores / hundreds
# of GB while the container quota is a small fraction of that.
set -euo pipefail

log() { printf '[entrypoint] %s\n' "$*"; }

STDB_ROOT="${STDB_ROOT:-/stdb}"
STDB_DATA_DIR="${STDB_DATA_DIR:-$STDB_ROOT/data}"
STDB_KEY_DIR="${STDB_KEY_DIR:-$STDB_ROOT/keys}"
STDB_LISTEN_PORT="${PORT:-3000}"
STDB_LOG_LEVEL="${STDB_LOG_LEVEL:-info}"
RUN_USER="${STDB_RUN_USER:-spacetime}"

# --- volume layout -----------------------------------------------------------
# Everything lives one level below the mount root so the `lost+found` directory
# every Railway volume ships never sits inside a directory the server scans.
umask 022
mkdir -p "$STDB_DATA_DIR" "$STDB_KEY_DIR"

if [ "$(id -u)" = "0" ]; then
  RUN_UID="$(id -u "$RUN_USER")"
  RUN_GID="$(id -g "$RUN_USER")"
  # Only chown when the owner actually disagrees: a full recursive chown of a
  # large commitlog on every boot is slow and pointless.
  if [ "$(stat -c '%u' "$STDB_ROOT")" != "$RUN_UID" ] \
     || [ "$(stat -c '%u' "$STDB_DATA_DIR")" != "$RUN_UID" ]; then
    log "taking ownership of $STDB_ROOT for $RUN_USER ($RUN_UID:$RUN_GID)"
    chown -R "$RUN_UID:$RUN_GID" "$STDB_ROOT"
  fi
  chmod 700 "$STDB_KEY_DIR"
fi

# --- config.toml -------------------------------------------------------------
# The server writes its own default config.toml on first boot, and that default
# sets several targets to `debug`, which on a busy instance runs straight into
# Railway's 500 logs/sec per-replica cap. Render a small one on every boot so
# the level stays operator-controllable through a Railway variable.
CONFIG_TOML="$STDB_DATA_DIR/config.toml"
cat > "$CONFIG_TOML" <<EOF
# Rendered by entrypoint.sh on every boot. Edit STDB_LOG_LEVEL / STDB_MODULE_HTTP
# on the Railway service rather than this file: it is overwritten each start.
[logs]
level = "${STDB_LOG_LEVEL}"

[module-http]
enabled = ${STDB_MODULE_HTTP:-true}
EOF
if [ "$(id -u)" = "0" ]; then
  chown "$RUN_USER" "$CONFIG_TOML"
fi

# --- cgroup-derived sizing ---------------------------------------------------
# `--page_pool_max_size` defaults to 8 GiB, which is larger than the memory
# quota of most Railway plans, so the process would be OOM-killed with no log
# line before the pool ever pushed back. Take half of the cgroup limit instead.
page_pool_bytes() {
  local limit=""
  if [ -r /sys/fs/cgroup/memory.max ]; then
    limit="$(cat /sys/fs/cgroup/memory.max)"
  elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    limit="$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)"
  fi
  case "$limit" in
    ''|max|*[!0-9]*) return 1 ;;
  esac
  # Ignore an absurd "limit" (an unconstrained cgroup reports a huge number).
  if [ "$limit" -gt 137438953472 ] 2>/dev/null; then return 1; fi
  # Half the quota, rounded down to a 64 KiB multiple, floor 256 MiB.
  local half=$(( limit / 2 / 65536 * 65536 ))
  if [ "$half" -lt 268435456 ]; then half=268435456; fi
  printf '%s' "$half"
}

STDB_ARGS=(
  start
  --data-dir "$STDB_DATA_DIR"
  --jwt-pub-key-path "$STDB_KEY_DIR/id_ecdsa.pub"
  --jwt-priv-key-path "$STDB_KEY_DIR/id_ecdsa"
  --listen-addr "[::]:${STDB_LISTEN_PORT}"
  --non-interactive
)

if [ -n "${STDB_PAGE_POOL_MAX_SIZE:-}" ]; then
  STDB_ARGS+=(--page_pool_max_size "$STDB_PAGE_POOL_MAX_SIZE")
elif POOL="$(page_pool_bytes)"; then
  log "page pool capped at ${POOL} bytes from the cgroup memory limit"
  STDB_ARGS+=(--page_pool_max_size "$POOL")
else
  log "could not read a cgroup memory limit; leaving the page pool at its default"
fi

# The server writes a copy of every log line under <data-dir>/logs unless this
# is set, which silently consumes the volume the database itself needs.
export SPACETIMEDB_DISABLE_DISK_LOGGING="${SPACETIMEDB_DISABLE_DISK_LOGGING:-1}"

log "listening on [::]:${STDB_LISTEN_PORT}, data dir ${STDB_DATA_DIR}"

if [ "$(id -u)" = "0" ]; then
  export HOME="/home/$RUN_USER"
  exec setpriv --reuid="$RUN_USER" --regid="$RUN_USER" --init-groups \
    /opt/spacetime/spacetimedb-standalone "${STDB_ARGS[@]}"
fi

exec /opt/spacetime/spacetimedb-standalone "${STDB_ARGS[@]}"

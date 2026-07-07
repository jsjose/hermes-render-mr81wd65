#!/bin/sh
# Entrypoint wrapper for the render-tools image.
#
# Runs as root (PID-1 child of tini). On every boot it:
#   1. Ensures /opt/data exists and is owned by hermes:hermes.
#   2. Runs the config patcher as the hermes user. The patcher is
#      idempotent: it only INSERTs the Render MCP server and the
#      skills.external_dirs entry; it never overwrites user edits.
#   3. Exec's the upstream entrypoint chain with the original args
#      (default CMD is `gateway run`).
#
# The upstream entrypoint also chowns /opt/data and drops to the hermes
# user via gosu for the gateway process. Our chown here is redundant in
# the happy path but harmless, and it lets the patcher run on a fresh
# disk that hasn't been chowned yet.

set -eu

DATA_DIR="${HERMES_HOME:-/opt/data}"
PATCHER="/opt/render-tools/patch-config.py"
BOOT_LOG="${DATA_DIR}/.render-tools-boot.log"

# Mirrors everything below to a file on the persistent disk, in addition
# to the normal stdout/stderr Render streams live. Render's log viewer
# can only show output from a container that reaches a healthy state;
# a container that crashes/times out before binding a port may have its
# early boot output lost entirely from the live log view. The disk
# survives across deploys, so this file lets you `cat` the full history
# of every boot attempt (including failed ones) from any later shell.
mkdir -p "${DATA_DIR}"
log() {
  msg="[render-tools] $(date -u +%FT%TZ) $*"
  echo "${msg}"
  echo "${msg}" >>"${BOOT_LOG}" 2>/dev/null || true
}

log "bootstrap starting (HERMES_DASHBOARD_BASIC_AUTH_USER set: $([ -n "${HERMES_DASHBOARD_BASIC_AUTH_USER:-}" ] && echo yes || echo no), HASH set: $([ -n "${HERMES_DASHBOARD_BASIC_AUTH_HASH:-}" ] && echo yes || echo no))"

# Make sure the data dir exists and the hermes user can write to it
# before we run the patcher. Idempotent — if /opt/data is already a
# mounted, chowned disk this is a no-op.
if ! chown -R hermes:hermes "${DATA_DIR}" 2>/dev/null; then
  log "warning: could not chown ${DATA_DIR}; continuing"
fi

# Patch config.yaml. We never fail the boot on a patch error — the agent
# can still run without the Render MCP server registered, and the user
# can always add it manually from the dashboard.
if [ -x "${PATCHER}" ]; then
  patch_output="$(gosu hermes "${PATCHER}" "${DATA_DIR}/config.yaml" 2>&1)" && patch_status=0 || patch_status=$?
  log "patcher output: ${patch_output}"
  if [ "${patch_status}" -ne 0 ]; then
    log "warning: config patch failed (exit ${patch_status}); continuing with unmodified config"
  fi
else
  log "warning: ${PATCHER} not found or not executable; skipping"
fi

log "bootstrap done, handing off to entrypoint"

# Hand off to the upstream entrypoint. The upstream script handles
# privilege drop, dashboard backgrounding, and the actual gateway exec.
exec /opt/hermes/docker/entrypoint.sh "$@"

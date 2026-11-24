#!/bin/bash
# Start Keeper's processes and exit non-zero as soon as one of them stops,
# so Railway's ON_FAILURE restart policy brings the service back.
set -euo pipefail

log() { printf '[keeper-railway] %s\n' "$*"; }
die() { log "ERROR: $*"; exit 1; }

export PATH="/command:${PATH}"   # s6-setuidgid lives here
: "${PORT:=8080}"
: "${DATABASE_URL:?DATABASE_URL is required (reference your Postgres service)}"
: "${REDIS_URL:?REDIS_URL is required (reference your Redis service)}"
: "${BETTER_AUTH_SECRET:?BETTER_AUTH_SECRET is required}"
: "${ENCRYPTION_KEY:?ENCRYPTION_KEY is required}"

# Public URL. Railway may resolve https://${{RAILWAY_PUBLIC_DOMAIN}} to a bare
# "https://" if no domain exists yet; fall back to the domain variable or localhost.
url="${BETTER_AUTH_URL:-}"
if ! [[ "$url" =~ ^https?://[^/]+ ]]; then
  if [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then url="https://${RAILWAY_PUBLIC_DOMAIN}"; else url="http://localhost:${PORT}"; fi
  log "BETTER_AUTH_URL is empty or invalid; using ${url}"
fi
export BETTER_AUTH_URL="${url%/}"
export MCP_PUBLIC_URL="${MCP_PUBLIC_URL:-${BETTER_AUTH_URL}/mcp}"

# Railway's private network is IPv6; ioredis defaults to IPv4 unless family=0.
if [[ "$REDIS_URL" != *family=* ]]; then
  if [[ "$REDIS_URL" == *\?* ]]; then REDIS_URL="${REDIS_URL}&family=0"; else REDIS_URL="${REDIS_URL}?family=0"; fi
fi
export REDIS_URL

# Keeper needs a base64-encoded 32-byte key. Accept that as is; otherwise derive
# one from whatever string was given (stable: same input, same key).
ENCRYPTION_KEY="$(ENCRYPTION_KEY="$ENCRYPTION_KEY" bun -e '
const k = process.env.ENCRYPTION_KEY;
const b = Buffer.from(k, "base64");
if (b.length === 32 && b.toString("base64") === k) { process.stdout.write(k); }
else { process.stdout.write(new Bun.CryptoHasher("sha256").update(k).digest("base64")); }')"
export ENCRYPTION_KEY

# Internal wiring (fixed in this image).
export ENV=production COMMERCIAL_MODE=false WORKER_JOB_QUEUE_ENABLED=true
export API_PORT=3001 MCP_PORT=3002
export VITE_API_URL=http://127.0.0.1:3001 VITE_MCP_URL=http://127.0.0.1:3002 MCP_API_URL=http://127.0.0.1:3001

# Sized for a small Railway service (0.5 GB on the Free plan). Override if you scale up.
export WORKER_CONCURRENCY="${WORKER_CONCURRENCY:-4}"
export INGEST_FLEET_CONCURRENCY="${INGEST_FLEET_CONCURRENCY:-8}"
export INGEST_WAKE_CONCURRENCY="${INGEST_WAKE_CONCURRENCY:-4}"
export INGEST_CLAIM_BATCH="${INGEST_CLAIM_BATCH:-20}"
export CRON_FLUSH_POOL_MAX="${CRON_FLUSH_POOL_MAX:-4}"
BUN_FLAGS="${BUN_FLAGS---smol}"   # smaller heap; set BUN_FLAGS= to turn off

# Memory: the separate Keeper processes need about 650 MB together. Below about
# 900 MB (Railway Free/Trial: 0.5 GB) run API, cron, worker and web in one Bun
# process with a capped heap and the MCP server off, unless KEEPER_LOW_MEMORY says otherwise.
mem_max="$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo max)"
low_mem="${KEEPER_LOW_MEMORY:-auto}"
if [ "$low_mem" = "auto" ]; then
  low_mem=false
  if [ "$mem_max" != "max" ] && [ "$mem_max" -lt 900000000 ] 2>/dev/null; then low_mem=true; fi
fi
if [ "$low_mem" = "true" ]; then
  log "Low-memory mode (${mem_max} bytes): one Bun process, MCP server off. Give the service 1 GB (Hobby plan) for the MCP server."
fi

# Database migrations (upstream script, guarded by a Postgres advisory lock).
log "Waiting for Postgres and running migrations"
for i in $(seq 1 60); do
  if bun /app/packages/database/scripts/migrate.ts; then ok=1; break; fi
  ok=0; log "Migration attempt $i failed; retrying in 3 s"; sleep 3
done
[ "${ok:-0}" = 1 ] || die "database migrations failed"

pids=()
names=()
start() { # name pool cmd...
  local name=$1 pool=$2; shift 2
  ( export DATABASE_POOL_MAX="${pool}"; exec "$@" ) &
  pids+=($!); names+=("$name")
  log "started ${name} (pid $!)"
}

cd /app
start api    "${API_POOL_MAX:-5}"    s6-setuidgid keeper bun ${BUN_FLAGS} run services/api/dist/index.js
for i in $(seq 1 90); do curl -sf http://127.0.0.1:3001/api/health >/dev/null && break; sleep 1; done
curl -sf http://127.0.0.1:3001/api/health >/dev/null || die "API did not become healthy"

# Create the admin account on first boot (sign-up is closed to the public).
/usr/local/bin/keeper-railway-bootstrap-admin || die "admin bootstrap failed; refusing to start with open sign-up"

W=/app/applications/web/dist/server-entry/index.js
if [ "$low_mem" = "true" ]; then
  # The API already runs on its own for the admin bootstrap; stop it and run
  # API, cron, worker and web in one Bun process with a capped heap.
  kill -TERM "${pids[0]}" 2>/dev/null || true; wait "${pids[0]}" 2>/dev/null || true
  pids=(); names=()
  unset MCP_PUBLIC_URL VITE_MCP_URL
  ( cd /app/applications/web && export DATABASE_POOL_MAX="${COMBINED_POOL_MAX:-8}" \
      BUN_JSC_forceRAMSize="${BUN_JSC_forceRAMSize:-268435456}" \
      KEEPER_MODULES="/app/services/api/dist/index.js,/app/services/cron/dist/index.js,/app/services/worker/dist/index.js,$W" \
      && exec s6-setuidgid keeper bun ${BUN_FLAGS} /etc/keeper-railway/guard.mjs ) &
  pids+=($!); names+=(keeper); log "started keeper (api, cron, worker, web in one process; pid $!)"
else
  start cron   "${CRON_POOL_MAX:-4}"   s6-setuidgid keeper bun ${BUN_FLAGS} run services/cron/dist/index.js
  start worker "${WORKER_POOL_MAX:-4}" s6-setuidgid keeper bun ${BUN_FLAGS} run services/worker/dist/index.js
  if [ "${KEEPER_MCP_ENABLED:-true}" = "true" ]; then
    start mcp  "${MCP_POOL_MAX:-2}"    s6-setuidgid keeper bun ${BUN_FLAGS} run services/mcp/dist/index.js
  else
    unset MCP_PUBLIC_URL VITE_MCP_URL
  fi
  ( cd /app/applications/web && export KEEPER_MODULES="$W" \
      && exec s6-setuidgid keeper bun ${BUN_FLAGS} /etc/keeper-railway/guard.mjs ) &
  pids+=($!); names+=(web); log "started web (pid $!)"
fi

shutdown() { log "stopping"; kill -TERM "${pids[@]}" 2>/dev/null || true; wait || true; exit 0; }
trap shutdown TERM INT

# Poll (BusyBox-style `wait -n` is unreliable): exit 1 as soon as any process stops.
while true; do
  for idx in "${!pids[@]}"; do
    if ! kill -0 "${pids[$idx]}" 2>/dev/null; then
      wait "${pids[$idx]}" && rc=0 || rc=$?
      log "ERROR: ${names[$idx]} exited with code ${rc}; stopping so Railway restarts the service"
      kill -TERM "${pids[@]}" 2>/dev/null || true
      sleep 2
      exit 1
    fi
  done
  sleep 2
done

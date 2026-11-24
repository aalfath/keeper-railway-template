#!/bin/bash
# Create Keeper's admin account from KEEPER_ADMIN_USERNAME / KEEPER_ADMIN_PASSWORD
# on first boot. Talks to the API on loopback, so it works while public sign-up
# is blocked. Exits non-zero if the account can't be created or confirmed.
set -euo pipefail
user="${KEEPER_ADMIN_USERNAME:-admin}"
pass="${KEEPER_ADMIN_PASSWORD:-}"
if [ -z "$pass" ]; then
  echo "[keeper-railway] ERROR: KEEPER_ADMIN_PASSWORD is empty" >&2; exit 1
fi
if [ "${#pass}" -lt 8 ]; then
  echo "[keeper-railway] ERROR: KEEPER_ADMIN_PASSWORD must be at least 8 characters" >&2; exit 1
fi
body="$(USER_="$user" PASS_="$pass" bun -e 'process.stdout.write(JSON.stringify({username:process.env.USER_,password:process.env.PASS_,name:process.env.USER_}))')"
out="$(curl -s -o /tmp/bootstrap.json -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' -H "Origin: ${BETTER_AUTH_URL}" \
  --data "$body" http://127.0.0.1:3001/api/auth/username-only/sign-up || true)"
if [ "$out" = "200" ]; then
  echo "[keeper-railway] created admin account '${user}'"
  exit 0
fi
if grep -qi 'already taken' /tmp/bootstrap.json 2>/dev/null; then
  echo "[keeper-railway] admin account '${user}' already exists"
  exit 0
fi
echo "[keeper-railway] ERROR: admin sign-up returned HTTP ${out}: $(head -c 300 /tmp/bootstrap.json 2>/dev/null)" >&2
exit 1

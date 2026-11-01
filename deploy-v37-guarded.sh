#!/usr/bin/env bash
# HOS150 v37 guarded web-only deployment; preserves SQLite and login portal.
set -Eeuo pipefail
ROOT=/srv/squeak-server/workspace/hos-150
cd "$ROOT"
test -s v37-driver-workspace.js
grep -q 'v37-driver-workspace.js' index.html
grep -q 'hos150_local_recovery_' server-sync.js
docker compose config -q
if command -v node >/dev/null 2>&1; then
  node --check v37-driver-workspace.js
  node --check server-sync.js
fi
python3 test_safety_config.py
systemctl start hos150-backup.service
tag="local/hos150:pre-v37-$(date -u +%Y%m%dT%H%M%SZ)"
docker tag local/hos150:36.0 "$tag"
echo "Preserved previous web image as: $tag"
started=0
rollback() {
  rc=$?
  trap - EXIT
  if (( rc != 0 )) && (( started == 1 )); then
    echo "V37 FAILED (exit $rc). Restoring the original HOS web image..."
    docker tag "$tag" local/hos150:36.0
    docker compose up -d --no-deps --no-build --force-recreate hos150
    if curl -fsS --max-time 5 http://127.0.0.1:3150/health >/dev/null; then
      echo "Original HOS 150 web service restored"
    else
      echo "WARNING: rollback local health check failed"
    fi
  fi
  exit "$rc"
}
trap rollback EXIT
echo "Building only the HOS150 web image..."
docker compose build hos150
started=1
docker compose up -d --no-deps --no-build hos150
ok=0
for i in $(seq 1 20); do
  if curl -fsS --max-time 3 http://127.0.0.1:3150/health >/dev/null &&
     curl -fsS --max-time 3 http://127.0.0.1:3150/v37-driver-workspace.js | grep -q 'HOS150 v37'; then
    ok=1
    break
  fi
  sleep 2
done
if (( ok != 1 )); then
  echo "V37 health failed: automatic rollback requested"
  exit 1
fi
echo "HOS150 V37 DEPLOY PASS | GET /health and v37-driver-workspace.js OK"
echo "Other containers and stored records were not replaced."

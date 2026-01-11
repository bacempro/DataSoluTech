#!/usr/bin/env bash
set -euo pipefail
echo "[mongo-init] Creating application user in '${MONGO_DB}'..."
mongosh --quiet <<EOF
use ${MONGO_DB}
if (db.getUser("${MONGO_APP_USER}") == null) {
  db.createUser({
    user: "${MONGO_APP_USER}",
    pwd: "${MONGO_APP_PASSWORD}",
    roles: [
      { role: "readWrite", db: "${MONGO_DB}" },
      { role: "dbAdmin", db: "${MONGO_DB}" }
    ]
  });
  print("[mongo-init] User '${MONGO_APP_USER}' created.");
} else {
  print("[mongo-init] User '${MONGO_APP_USER}' already exists; skipping.");
}
EOF
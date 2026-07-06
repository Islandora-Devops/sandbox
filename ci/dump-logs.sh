#!/usr/bin/env bash
set -euo pipefail

domain="${1:?Usage: dump-logs.sh <domain>}"

key_file="$(mktemp)"
trap 'rm -f "$key_file"' EXIT

printf '%s\n' "${PACKER_SSH_KEY:?PACKER_SSH_KEY must be set}" > "$key_file"
chmod 600 "$key_file"

echo "=== Logs from ${domain} ==="
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$key_file" "cloud-compose@${domain}" '
  set -u

  sudo journalctl -u cloud-init --no-pager -n 80 || true
  sudo journalctl -u cloud-compose.service -u rake.service -u cloud-compose-mariadb-backup.service --no-pager -n 160 || true
  sudo tail -n 160 /home/cloud-compose/run.log || true
  docker ps || true

  if [ -f /home/cloud-compose/profile.sh ] && [ -f /home/cloud-compose/compose-apps.sh ]; then
    # shellcheck disable=SC1091
    source /home/cloud-compose/profile.sh
    # shellcheck disable=SC1091
    source /home/cloud-compose/compose-apps.sh

    app="${CLOUD_COMPOSE_PRIMARY_APP:-}"
    if [ -z "$app" ]; then
      app="$(compose_app_names | head -n 1)"
    fi
    if [ -n "$app" ]; then
      source_compose_app_env "$app"
      cd "$DOCKER_COMPOSE_DIR" && docker compose logs --tail 50 || true
    fi
  fi
' || echo "Could not reach ${domain}"

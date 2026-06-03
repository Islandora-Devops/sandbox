#!/usr/bin/env bash
set -euo pipefail

domain="${1:?Usage: dump-logs.sh <domain>}"

key_file="$(mktemp)"
trap 'rm -f "$key_file"' EXIT

echo "${PACKER_SSH_KEY:?PACKER_SSH_KEY must be set}" > "$key_file"
chmod 600 "$key_file"

echo "=== Logs from ${domain} ==="
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i "$key_file" "core@${domain}" \
  "sudo journalctl -u isle-init.service --no-pager -n 100;
   sudo journalctl -u sandbox.service --no-pager -n 50;
   cd /opt/sandbox/isle-site-template;
   docker compose logs --tail 25" || echo "Could not reach ${domain}"

#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source /home/cloud-compose/profile.sh
# shellcheck disable=SC1091
source /home/cloud-compose/compose-apps.sh

app="${CLOUD_COMPOSE_PRIMARY_APP:-}"
if [ -z "$app" ]; then
  app="$(compose_app_names | head -n 1)"
fi

if [ -z "$app" ]; then
  echo "No cloud-compose app configured for rake" >&2
  exit 1
fi

source_compose_app_env "$app"

cd "$DOCKER_COMPOSE_DIR"
export GITHUB_ACTIONS=true
export TERM=xterm

if make -n demo-objects >/dev/null 2>&1; then
  docker compose down -v
  make demo-objects
else
  sitectl compose --context "$SITECTL_CONTEXT_NAME" up -d --remove-orphans
fi

sitectl healthcheck \
  --context "$SITECTL_CONTEXT_NAME" \
  --persist \
  --timeout "$SITECTL_HEALTHCHECK_TIMEOUT" \
  --interval "$SITECTL_HEALTHCHECK_INTERVAL"

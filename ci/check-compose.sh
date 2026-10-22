#!/usr/bin/env bash
# Validate the sandbox override against a checkout of isle-site-template.
set -euo pipefail

template_dir=${1:?Usage: ci/check-compose.sh /path/to/isle-site-template}
repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CAPTCHA_SECRET=validation DOMAIN=example.org docker compose \
  --env-file "$repo_dir/.env" \
  -f "$template_dir/docker-compose.yml" \
  -f "$repo_dir/rootfs/opt/sandbox/compose.override.yaml" config --format json |
  python3 -c '
import json, sys
traefik = json.load(sys.stdin)["services"]["traefik"]
assert "--entryPoints.https.http.middlewares=captcha-protect@docker" in traefik["command"]
assert "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=http" in traefik["command"]
assert traefik["labels"]["traefik.http.middlewares.captcha-protect.plugin.captcha-protect.captchaProvider"] == "poj"
mounts = {v["target"]: v for v in traefik["volumes"]}
assert mounts["/acme"]["source"] == "/opt/sandbox/acme"
assert mounts["/plugins-local/src/github.com/libops/captcha-protect"]["read_only"]
print("Sandbox Compose configuration passed")
'

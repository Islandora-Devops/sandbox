#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source /opt/sandbox/profile.sh

# Install docker-compose (replaces install-docker-compose.service)
if [ ! -f "/usr/local/lib/docker/cli-plugins/docker-compose" ]; then
  mkdir -p /usr/local/lib/docker/cli-plugins
  retry_until_success curl -sSL \
    https://github.com/docker/compose/releases/download/v5.1.0/docker-compose-linux-x86_64 \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod a+x /usr/local/lib/docker/cli-plugins/docker-compose
fi

# Install docker-buildx (replaces install-buildx.service)
if [ ! -f "/usr/local/lib/docker/cli-plugins/docker-buildx" ]; then
  retry_until_success curl -sSL \
    https://github.com/docker/buildx/releases/download/v0.32.0/buildx-v0.32.0.linux-amd64 \
    -o /usr/local/lib/docker/cli-plugins/docker-buildx
  chmod a+x /usr/local/lib/docker/cli-plugins/docker-buildx
fi

# Install make (replaces install-make.service)
if [ ! -f /usr/bin/make ]; then
  rpm-ostree install --apply-live make
fi

# Clone and initialise isle-site-template (replaces setup-sandbox.service)
REPO_URL=$(cat /opt/sandbox/.repo-url)
REPO_BRANCH=$(cat /opt/sandbox/.repo-branch)
if [ ! -d /opt/sandbox/isle-site-template ]; then
  retry_until_success git clone \
    --branch "$REPO_BRANCH" \
    --single-branch \
    "$REPO_URL" \
    /opt/sandbox/isle-site-template
fi

pushd /opt/sandbox/isle-site-template

cp /opt/sandbox/.env .
cp /opt/sandbox/docker-compose.override.yml .

mkdir -p ./secrets
cp /opt/sandbox/.secrets/ACTIVEMQ_WEB_ADMIN_PASSWORD ./secrets/ACTIVEMQ_WEB_ADMIN_PASSWORD
cp /opt/sandbox/.secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD ./secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD

export GITHUB_ACTIONS="true"
export TERM="${TERM:-dumb}"
make init build demo-objects

popd

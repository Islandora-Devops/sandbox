#!/usr/bin/env bash

set -euo pipefail

# renovate: datasource=github-releases depName=docker-compose packageName=docker/compose
DOCKER_COMPOSE_VERSION=v5.5.1
# renovate: datasource=github-releases depName=docker-buildx packageName=docker/buildx
DOCKER_BUILDX_VERSION=v0.37.0

# shellcheck disable=SC1091
source /opt/sandbox/profile.sh

install -d /etc/yum.repos.d
cat >/etc/yum.repos.d/sitectl.repo <<'EOF'
[sitectl]
name=sitectl
baseurl=https://packages.libops.io/sitectl/rpm
enabled=1
gpgcheck=0
repo_gpgcheck=1
gpgkey=https://packages.libops.io/sitectl/sitectl-archive-keyring.asc
EOF

# Install docker-compose (replaces install-docker-compose.service)
if [ ! -f "/usr/local/lib/docker/cli-plugins/docker-compose" ]; then
  mkdir -p /usr/local/lib/docker/cli-plugins
  retry_until_success curl -sSL \
    "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod a+x /usr/local/lib/docker/cli-plugins/docker-compose
fi

# Install docker-buildx (replaces install-buildx.service)
if [ ! -f "/usr/local/lib/docker/cli-plugins/docker-buildx" ]; then
  retry_until_success curl -sSL \
    "https://github.com/docker/buildx/releases/download/${DOCKER_BUILDX_VERSION}/buildx-${DOCKER_BUILDX_VERSION}.linux-amd64" \
    -o /usr/local/lib/docker/cli-plugins/docker-buildx
  chmod a+x /usr/local/lib/docker/cli-plugins/docker-buildx
fi

# Install host packages (replaces install-make.service)
packages=()
if [ ! -f /usr/bin/make ]; then
  packages+=(make)
fi
if ! rpm -q sitectl-isle >/dev/null 2>&1; then
  packages+=(sitectl-isle)
fi
if [ "${#packages[@]}" -gt 0 ]; then
  rpm-ostree install --apply-live "${packages[@]}"
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
export HOME=/var/home/core
sitectl config set-context sandbox \
  --type local \
  --plugin isle \
  --project-dir /opt/sandbox/isle-site-template \
  --project-name sandbox

sitectl component set bot-mitigation on --yolo
sitectl component set isle-tls enabled --tls-mode letsencrypt --yolo

cp /opt/sandbox/.env .
cp /opt/sandbox/docker-compose.override.yml .

mkdir -p ./secrets
cp /opt/sandbox/.secrets/ACTIVEMQ_WEB_ADMIN_PASSWORD ./secrets/ACTIVEMQ_WEB_ADMIN_PASSWORD
cp /opt/sandbox/.secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD ./secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD
chown -R core:core /opt/sandbox/isle-site-template

sed -i '/^# sandbox local loopback start$/,/^# sandbox local loopback end$/d' /etc/hosts
{
  echo "# sandbox local loopback start"
  printf '127.0.0.1 %s activemq.%s blazegraph.%s fcrepo.%s solr.%s\n' \
    "$DOMAIN" "$DOMAIN" "$DOMAIN" "$DOMAIN" "$DOMAIN"
  echo "# sandbox local loopback end"
} >> /etc/hosts

CORE_HOME="$(getent passwd core | cut -d: -f6)"
runuser -u core -- env GITHUB_ACTIONS=true HOME="$CORE_HOME" TERM=xterm bash -lc 'cd /opt/sandbox/isle-site-template && make init build demo-objects'

popd

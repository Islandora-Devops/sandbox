#!/usr/bin/env bash

set -euo pipefail

git clone https://github.com/islandora-devops/isle-site-template /opt/sandbox/isle-site-template
pushd /opt/sandbox/isle-site-template

cp /opt/sandbox/.env .
mkdir -p ./secrets
cp /opt/sandbox/.secrets/ACTIVEMQ_WEB_ADMIN_PASSWORD ./secrets/ACTIVEMQ_WEB_ADMIN_PASSWORD
cp /opt/sandbox/.secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD ./secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD

make init build demo-objects

#!/usr/bin/env bash

set -euo pipefail

git clone https://github.com/islandora-devops/isle-site-template /opt/sandbox/isle-site-template
pushd /opt/sandbox/isle-site-template

cp /opt/sandbox/.env .

sed -i '/^      --ping=true$/i\
      --entrypoints.https.http.tls.certResolver=letsencrypt\
      --certificatesresolvers.letsencrypt.acme.httpchallenge=true\
      --certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=http\
      --certificatesresolvers.letsencrypt.acme.storage=/acme/acme.json\
      --certificatesresolvers.letsencrypt.acme.email=community@islandora.ca\
      --certificatesresolvers.letsencrypt.acme.caserver=https://acme-v02.api.letsencrypt.org/directory' docker-compose.yml

mkdir -p ./secrets
cp /opt/sandbox/.secrets/ACTIVEMQ_WEB_ADMIN_PASSWORD ./secrets/ACTIVEMQ_WEB_ADMIN_PASSWORD
cp /opt/sandbox/.secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD ./secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD

export GITHUB_ACTIONS="true"
make init build demo-objects

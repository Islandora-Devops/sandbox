# syntax=docker/dockerfile:1.5.1
ARG REPOSITORY
ARG TAG
FROM ${REPOSITORY}/drupal:${TAG} AS workbench

ARG TARGETARCH
ARG WORKBENCH_COMMIT=b0dcc1b
ARG WORKBENCH_FILE=${WORKBENCH_COMMIT}.tar.gz
ARG WORKBENCH_URL=https://github.com/mjordan/islandora_workbench/archive/${WORKBENCH_FILE}
ARG WORKBENCH_SHA256=e5ea72bd5661c46ee9f434dbc7cf31839365c934d120b2310204ac3f4e3464f4

RUN --mount=type=cache,id=sandbox-apk-${TARGETARCH},sharing=locked,target=/var/cache/apk \
    apk add \
      build-base \
      py3-setuptools \
      py3-urllib3 \
      py3-pip \
      python3 \
      python3-dev

RUN --mount=type=cache,id=sandbox-downloads-${TARGETARCH},sharing=locked,target=/opt/downloads \
    download.sh \
        --url "${WORKBENCH_URL}" \
        --sha256 "${WORKBENCH_SHA256}" \
        --strip \
        --dest "/var/www/drupal/islandora_workbench" \
    && \
    cd /var/www/drupal/islandora_workbench && \
    pip install --target=. . && \
    chown -R nginx:nginx /var/www/drupal/islandora_workbench

FROM ${REPOSITORY}/drupal:${TAG} AS demo

ARG TARGETARCH

ARG DEMO_OBJECTS_COMMIT=e5000eb
ARG DEMO_OBJECTS_FILE=${DEMO_OBJECTS_COMMIT}.tar.gz
ARG DEMO_OBJECTS_URL=https://github.com/Islandora-Devops/islandora_demo_objects/archive/${DEMO_OBJECTS_FILE}
ARG DEMO_OBJECTS_SHA256=9096e9ad674d70af468d2a50274875e3d555877ddea2d5f284f2a40fe6535fb9

RUN --mount=type=cache,id=sandbox-downloads-${TARGETARCH},sharing=locked,target=/opt/downloads \
    download.sh \
        --url "${DEMO_OBJECTS_URL}" \
        --sha256 "${DEMO_OBJECTS_SHA256}" \
        --strip \
        --dest "/var/www/drupal/islandora_demo_objects" \
    && \
    chown -R nginx:nginx /var/www/drupal/islandora_demo_objects

FROM ${REPOSITORY}/drupal:${TAG} AS starter

ARG TARGETARCH
ARG STARTER_SITE_COMMIT=db2ecb0
ARG STARTER_SITE_FILE=${STARTER_SITE_COMMIT}.tar.gz
ARG STARTER_SITE_URL=https://github.com/Islandora-Devops/islandora-starter-site/archive/${STARTER_SITE_FILE}
ARG STARTER_SITE_SHA256=cc14a6f86d072b3e75720a1d73fca37fb466662db9aeba51a97cfbed0076444b

RUN --mount=type=cache,id=sandbox-downloads-${TARGETARCH},sharing=locked,target=/opt/downloads \
    download.sh \
        --url "${STARTER_SITE_URL}" \
        --sha256 "${STARTER_SITE_SHA256}" \
        --strip \
        --dest "/var/www/drupal"

RUN --mount=type=bind,source=rootfs/var/www/drupal/assets/patches/default_settings.txt,target=/tmp/default_settings.txt \
    --mount=type=bind,source=rootfs/var/www/drupal/assets/patches/olivero.theme,target=/tmp/olivero.theme \
    --mount=type=cache,id=test-drupal-composer-${TARGETARCH},sharing=locked,target=/root/.composer/cache \
    cp /tmp/default_settings.txt /var/www/drupal/assets/patches/default_settings.txt && \
    cp /tmp/olivero.theme /var/www/drupal/assets/patches/olivero.theme && \
    composer config extra.drupal-scaffold.file-mapping --merge --json '{"[web-root]/core/themes/olivero/olivero.theme":{"mode":"append","default":"web/core/themes/olivero/olivero.theme","append":"assets/patches/olivero.theme"}}' && \
    composer install -d /var/www/drupal && \
    chown -R nginx:nginx /var/www/drupal

FROM ${REPOSITORY}/drupal:${TAG}

ARG TARGETARCH

RUN --mount=type=cache,id=sandbox-apk-${TARGETARCH},sharing=locked,target=/var/cache/apk \
    apk add \
      py3-urllib3 \
      python3

# 30 minutes to startup on slower hardware.
# It can take a long time for workbench to ingest content.
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=1800000

COPY --link --from=workbench /var/www/drupal/islandora_workbench /var/www/drupal/islandora_workbench
COPY --link --from=demo /var/www/drupal/islandora_demo_objects /var/www/drupal/islandora_demo_objects
COPY --link --from=starter /var/www/drupal /var/www/drupal
COPY --link rootfs /
COPY --chown=nginx:nginx rootfs/var/www/drupal /var/www/drupal

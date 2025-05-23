# syntax=docker/dockerfile:1.5.1
ARG REPOSITORY
ARG TAG
FROM ${REPOSITORY}/drupal:${TAG} AS workbench

ARG TARGETARCH
ARG WORKBENCH_COMMIT=4c44e30421db71ff6b9984c30c552e1646f2ccfc
ARG WORKBENCH_FILE=${WORKBENCH_COMMIT}.tar.gz
ARG WORKBENCH_URL=https://github.com/mjordan/islandora_workbench/archive/${WORKBENCH_FILE}
ARG WORKBENCH_SHA256=918d0c9c186295b971bb325018a2cd73ec92ce25c7771337e3374f5eb41cd70f

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

ARG DEMO_OBJECTS_COMMIT=00c2f1e
ARG DEMO_OBJECTS_FILE=${DEMO_OBJECTS_COMMIT}.tar.gz
ARG DEMO_OBJECTS_URL=https://github.com/Islandora-Devops/islandora_demo_objects/archive/${DEMO_OBJECTS_FILE}
ARG DEMO_OBJECTS_SHA256=f13f17f3b75bceb5e25db2ad91987fea4523c674e6a4bbf9afd849de51b57d83

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
ARG STARTER_SITE_COMMIT=35c632485a65bbd2f5412b640b7e437294f39b20
ARG STARTER_SITE_FILE=${STARTER_SITE_COMMIT}.tar.gz
ARG STARTER_SITE_URL=https://github.com/Islandora-Devops/islandora-starter-site/archive/${STARTER_SITE_FILE}
ARG STARTER_SITE_SHA256=6a5482a4b935fc527119c57b8cba69983bedd1b6dee0d5228550128e1ad1d07a

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

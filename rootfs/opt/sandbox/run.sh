#!/usr/bin/env bash

set -eou pipefail
set -x

# shellcheck disable=SC1091
source /opt/sandbox/profile.sh

bash /opt/sandbox/setup.sh

systemctl start sandbox.service
systemctl start rake.timer

#!/usr/bin/env bash

set -eou pipefail

# shellcheck disable=SC1091
source /opt/sandbox/profile.sh

bash /opt/sandbox/setup.sh

systemctl start rake.timer

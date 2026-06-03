#!/usr/bin/env bash
set -euo pipefail

ci/deploy-local.sh test apply
ci/deploy-local.sh prod apply
ci/deploy-local.sh test cleanup

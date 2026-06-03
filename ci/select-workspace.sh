#!/usr/bin/env bash
set -euo pipefail

workspace="${1:?usage: ci/select-workspace.sh <workspace>}"

terraform workspace select "$workspace" >/dev/null 2>&1 || terraform workspace new "$workspace" >/dev/null

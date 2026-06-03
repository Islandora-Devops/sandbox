#!/usr/bin/env bash
set -euo pipefail

workspace="${1:?usage: ci/apply.sh <workspace>}"

case "$workspace" in
  test)
    ci/deploy-local.sh test apply
    ;;
  sandbox|prod)
    ci/deploy-local.sh prod apply
    ;;
  *)
    echo "Unsupported workspace for ci/apply.sh: ${workspace}" >&2
    exit 1
    ;;
esac

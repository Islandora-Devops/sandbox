#!/usr/bin/env bash
set -euo pipefail

workspace="${1:?usage: ci/destroy.sh <workspace>}"

case "$workspace" in
  test)
    ci/deploy-local.sh test destroy
    ;;
  sandbox|prod)
    echo "Destroy is disabled for prod/sandbox" >&2
    exit 1
    ;;
  *)
    echo "Unsupported workspace for ci/destroy.sh: ${workspace}" >&2
    exit 1
    ;;
esac

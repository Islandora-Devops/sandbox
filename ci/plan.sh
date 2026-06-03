#!/usr/bin/env bash
set -euo pipefail

workspace="${1:?usage: ci/plan.sh <workspace> [output-name]}"
output_name="${2:-plan}"

case "$workspace" in
  test)
    environment="test"
    ;;
  sandbox|prod)
    environment="prod"
    ;;
  *)
    echo "Unsupported workspace for ci/plan.sh: ${workspace}" >&2
    exit 1
    ;;
esac

TF_OUTPUT_NAME="$output_name" ci/deploy-local.sh "$environment" plan

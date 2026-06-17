#!/usr/bin/env bash
set -euo pipefail

workspace="${1:?usage: ci/delete-workspace.sh <workspace>}"

if [[ "$workspace" == "default" ]]; then
  echo "refusing to delete the default workspace" >&2
  exit 1
fi

if terraform workspace list | sed 's/^[* ]*//' | grep -qx "$workspace"; then
  terraform workspace select default >/dev/null 2>&1
  terraform workspace delete "$workspace"
fi

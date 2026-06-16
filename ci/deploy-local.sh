#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ci/deploy-local.sh test <plan|apply|cleanup|destroy>
  ci/deploy-local.sh prod <plan|apply>

Required environment:
  DIGITALOCEAN_TOKEN       DigitalOcean API token
  AWS_ACCESS_KEY_ID        Spaces access key for Terraform remote state
  AWS_SECRET_ACCESS_KEY    Spaces secret key for Terraform remote state
  ISLE_PASSWORD            Password used for Islandora default/admin secrets

Optional environment:
  ACTION                         Makefile action selector. Defaults to plan.
  DIGITALOCEAN_CANDIDATE_REGIONS Space-separated region preference list for test. Defaults to "tor1 nyc3 sfo3".
  SANDBOX_REGION                  Default sandbox/prod region. Defaults to "tor1".
  REQUIRED_NODE_IDS              Space-separated Drupal node IDs to validate after apply. Defaults to "20 50".
  TF_VAR_droplet_size            DigitalOcean size slug. Defaults to "s-4vcpu-8gb-amd".
  TF_VAR_region                  DigitalOcean region override. When unset, test selects an available region and prod uses SANDBOX_REGION.
  TF_OUTPUT_NAME                 GitHub Actions output name for plan output.
  ALLOW_FULL_TEST_DESTROY        Set to "true" to permit ACTION=destroy for the test workspace.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

require_env() {
  if [[ -z "${!1:-}" ]]; then
    echo "$1 is required" >&2
    exit 1
  fi
}

select_workspace() {
  local workspace="$1"
  terraform workspace select "$workspace" >/dev/null 2>&1 || terraform workspace new "$workspace" >/dev/null
}

export_plan_output() {
  local output_name="$1" plan_output="$2"

  if [[ -z "${GITHUB_OUTPUT:-}" || -z "$output_name" ]]; then
    return
  fi

  {
    echo "${output_name}<<TFEOF"
    printf '%s\n' "$plan_output"
    echo "TFEOF"
  } >> "$GITHUB_OUTPUT"
}

if [[ "$#" -lt 2 ]]; then
  usage
  exit 1
fi

environment="$1"
action="$2"

case "$environment" in
  test)
    workspace="test"
    domain="${TEST_DOMAIN:-test.islandora.ca}"
    ;;
  prod)
    workspace="sandbox"
    domain="${SANDBOX_DOMAIN:-sandbox.islandora.ca}"
    ;;
  *)
    echo "Unknown environment: ${environment}" >&2
    usage
    exit 1
    ;;
esac

case "$action" in
  plan|apply|destroy|cleanup) ;;
  *)
    echo "Unknown action: ${action}" >&2
    usage
    exit 1
    ;;
esac

if [[ "$environment" == "prod" && "$action" == "destroy" ]]; then
  echo "destroy is disabled for prod/sandbox" >&2
  exit 1
fi

if [[ "$environment" == "test" && "$action" == "destroy" && "${ALLOW_FULL_TEST_DESTROY:-}" != "true" ]]; then
  cat >&2 <<'EOF'
ACTION=destroy removes the entire test workspace, including DNS and the reserved IP.
Use ACTION=cleanup to destroy only ephemeral test compute.
To intentionally remove the entire test workspace, rerun with ALLOW_FULL_TEST_DESTROY=true.
EOF
  exit 1
fi

require_cmd curl
require_cmd jq
require_cmd terraform

export TEST_DOMAIN="${TEST_DOMAIN:-test.islandora.ca}"
export SANDBOX_DOMAIN="${SANDBOX_DOMAIN:-sandbox.islandora.ca}"
export PROD_DOMAIN="${PROD_DOMAIN:-$SANDBOX_DOMAIN}"
export REQUIRED_NODE_IDS="${REQUIRED_NODE_IDS:-20 50}"
export TF_VAR_droplet_size="${TF_VAR_droplet_size:-s-4vcpu-8gb-amd}"
export DIGITALOCEAN_CANDIDATE_REGIONS="${DIGITALOCEAN_CANDIDATE_REGIONS:-tor1 nyc3 sfo3}"
require_env DIGITALOCEAN_TOKEN
require_env AWS_ACCESS_KEY_ID
require_env AWS_SECRET_ACCESS_KEY
export SPACES_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export SPACES_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"

if [[ "$action" != "destroy" && "$action" != "cleanup" ]]; then
  require_env ISLE_PASSWORD
  export TF_VAR_isle_password="${TF_VAR_isle_password:-$ISLE_PASSWORD}"
else
  export TF_VAR_isle_password="${TF_VAR_isle_password:-placeholder}"
fi

if [[ -z "${TF_VAR_region:-}" && "$environment" == "prod" ]]; then
  export TF_VAR_region="${SANDBOX_REGION:-tor1}"
elif [[ -z "${TF_VAR_region:-}" ]]; then
  export TF_VAR_region
  TF_VAR_region="$("$repo_root/ci/select-region.sh" "$TF_VAR_droplet_size")"
fi

auto_approve_args=()
if [[ -n "${GITHUB_ACTION:-}" ]]; then
  auto_approve_args=(-auto-approve)
fi

cd "$repo_root"

terraform init -upgrade
select_workspace "$workspace"

if [[ "$action" != "destroy" && "$action" != "cleanup" ]]; then
  terraform validate
fi

case "$action" in
  plan)
    raw_plan_output="$(terraform plan -no-color)"
    plan_output="$(printf '%s\n' "$raw_plan_output" | grep -v -E '^(module\..+|Reading|Read complete|Refreshing state)' || true)"
    printf '%s\n' "$plan_output"
    export_plan_output "${TF_OUTPUT_NAME:-}" "$plan_output"
    ;;
  apply)
    echo "Applying ${workspace} in DigitalOcean region ${TF_VAR_region}"
    terraform apply "${auto_approve_args[@]}"
    "$repo_root/ci/health-check.sh" "https://${domain}"
    if [[ "$environment" == "test" ]]; then
      "$repo_root/ci/screenshot.sh" "https://${domain}" "$repo_root/artifacts/test-islandora-ca.png"
      "$repo_root/ci/fetch-json.sh" "https://${domain}/node/20?_format=jsonld" "$repo_root/artifacts/test-node-20.json"
    fi
    ;;
  destroy)
    terraform destroy "${auto_approve_args[@]}"
    if [[ "$environment" == "test" ]]; then
      terraform workspace select default >/dev/null 2>&1
      terraform workspace delete "$workspace"
    fi
    ;;
  cleanup)
    if [[ "$environment" != "test" ]]; then
      echo "cleanup is only supported for the test environment" >&2
      exit 1
    fi
    terraform destroy "${auto_approve_args[@]}" \
      -target='module.environment["test"].digitalocean_reserved_ip_assignment.this' \
      -target='module.environment["test"].digitalocean_droplet.this' \
      -target='terraform_data.workspace_guard'
    ;;
esac

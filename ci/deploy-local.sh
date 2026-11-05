#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage:
  ci/deploy-local.sh prod <plan|apply>

Required environment:
  DIGITALOCEAN_TOKEN       DigitalOcean API token
  AWS_ACCESS_KEY_ID        Spaces access key for Terraform remote state
  AWS_SECRET_ACCESS_KEY    Spaces secret key for Terraform remote state
  ISLE_PASSWORD            Password used for Islandora default/admin secrets
  PACKER_SSH_KEY           SSH private key used for deployment

Optional environment:
  ACTION                         Makefile action selector. Defaults to plan.
  SANDBOX_REGION                  Default sandbox region. Defaults to "tor1".
  REQUIRED_NODE_IDS              Space-separated Drupal node IDs to validate after apply. Defaults to "20 50".
  BOOTSTRAP_TIMEOUT_SECONDS       Maximum wait for candidate bootstrap. Defaults to 3600.
  TF_VAR_droplet_size            DigitalOcean size slug. Defaults to "s-4vcpu-8gb-amd".
  DIGITALOCEAN_FALLBACK_SIZES    Space-separated fallback sizes for unavailable capacity. Defaults to "s-4vcpu-8gb".
  TF_VAR_region                  DigitalOcean region override.
  TF_OUTPUT_NAME                 GitHub Actions output name for plan output.
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

if [[ "$environment" != "prod" || ( "$action" != "plan" && "$action" != "apply" ) ]]; then
  usage
  exit 1
fi
workspace="sandbox"

require_cmd curl
require_cmd jq
require_cmd terraform
require_cmd ssh-keygen
require_cmd python3

export SANDBOX_DOMAIN="${SANDBOX_DOMAIN:-sandbox.islandora.ca}"
export PROD_DOMAIN="${PROD_DOMAIN:-$SANDBOX_DOMAIN}"
export REQUIRED_NODE_IDS="${REQUIRED_NODE_IDS:-20 50}"
export TF_VAR_droplet_size="${TF_VAR_droplet_size:-s-4vcpu-8gb-amd}"
require_env DIGITALOCEAN_TOKEN
require_env AWS_ACCESS_KEY_ID
require_env AWS_SECRET_ACCESS_KEY
export SPACES_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export SPACES_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"

require_env ISLE_PASSWORD
require_env PACKER_SSH_KEY
export TF_VAR_isle_password="${TF_VAR_isle_password:-$ISLE_PASSWORD}"

key_file="$(mktemp)"
trap 'rm -f "$key_file"' EXIT
chmod 600 "$key_file"
printf '%s\n' "$PACKER_SSH_KEY" > "$key_file"
if ! TF_VAR_packer_ssh_public_key="$(ssh-keygen -y -P '' -f "$key_file" </dev/null)"; then
  echo 'PACKER_SSH_KEY must be a valid unencrypted SSH private key.' >&2
  exit 1
fi
export TF_VAR_packer_ssh_public_key

github_keys=""
github_users="$(curl -fsSL --connect-timeout 15 --max-time 60 \
  'https://islandora.github.io/documentation/contributing/committers/' |
  python3 "$repo_root/ci/committer-usernames.py")"
for github_user in $github_users; do
  keys="$(curl -fsSL --connect-timeout 15 --max-time 60 "https://github.com/${github_user}.keys")" || {
    echo "Could not fetch SSH keys for GitHub user ${github_user}." >&2
    exit 1
  }
  if [[ -z "$keys" ]]; then
    echo "GitHub user ${github_user} has no public SSH keys." >&2
  fi
  github_keys="${github_keys}"$'\n'"${keys}"
done
export TF_VAR_github_ssh_keys
TF_VAR_github_ssh_keys="$(printf '%s\n' "$github_keys" | jq -Rsc 'split("\n") | map(select(length > 0)) | unique')"

export TF_VAR_region="${TF_VAR_region:-${SANDBOX_REGION:-tor1}}"

cd "$repo_root"

terraform init -upgrade
select_workspace "$workspace"

terraform validate

case "$action" in
  plan)
    raw_plan_output="$(ci/deploy-blue-green.sh plan)"
    plan_output="$(printf '%s\n' "$raw_plan_output" | grep -v -E '^(module\..+|Reading|Read complete|Refreshing state)' || true)"
    printf '%s\n' "$plan_output"
    export_plan_output "${TF_OUTPUT_NAME:-}" "$plan_output"
    ;;
  apply)
    echo "Applying ${workspace} in DigitalOcean region ${TF_VAR_region}"
    "$repo_root/ci/deploy-blue-green.sh" apply
    ;;
esac

#!/usr/bin/env bash
set -euo pipefail

# Called after Terraform has selected the sandbox workspace.
: "${DIGITALOCEAN_TOKEN:?DIGITALOCEAN_TOKEN must be set}"
: "${SANDBOX_DOMAIN:?SANDBOX_DOMAIN must be set}"
action="${1:-apply}"

module='module.environment["sandbox"]'
state="$(terraform state pull)"
resource() {
  jq -er --arg address "$1" '
    [.resources[] as $resource | $resource.instances[] |
      (($resource.module // "") + "." + $resource.type + "." + $resource.name +
        (if .index_key == null then "" else "[" + (.index_key | tojson) + "]" end)) as $instance_address |
      select($instance_address == $address and .deposed == null) | .attributes][0] // empty
  ' <<< "$state"
}
reserved="$(resource "${module}.digitalocean_reserved_ip.this")"
reserved_ip="$(jq -er .ip_address <<< "$reserved")"
reserved_region="$(jq -er .region <<< "$reserved")"
if [[ "$reserved_region" != "${TF_VAR_region:?TF_VAR_region must be set}" ]]; then
  echo "Reserved IP is in ${reserved_region}; the sandbox candidate must use that region." >&2
  exit 1
fi
blue="$(resource "${module}.digitalocean_droplet.this[\"blue\"]" 2>/dev/null || true)"
green="$(resource "${module}.digitalocean_droplet.this[\"green\"]" 2>/dev/null || true)"
if [[ -z "$blue" ]]; then
  blue="$(resource "${module}.digitalocean_droplet.this" 2>/dev/null || true)"
fi
if [[ -z "$blue" && -z "$green" ]]; then
  echo 'No sandbox slots found in state. Move the existing droplet to the blue slot before deploying.' >&2
  exit 1
fi

assigned_id() {
  local response
  if ! response="$(curl --fail --silent --show-error --max-time 30 \
    -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
    "https://api.digitalocean.com/v2/reserved_ips/${reserved_ip}")"; then
    echo 'Could not read the reserved IP from DigitalOcean. Check DIGITALOCEAN_TOKEN and its permissions.' >&2
    return 1
  fi
  jq -er '.reserved_ip.droplet.id' <<< "$response"
}
live_id="$(assigned_id)"
if [[ -n "$blue" && "$(jq -r .id <<< "$blue")" == "$live_id" ]]; then
  active=blue; candidate=green; live="$blue"; stale="$green"
elif [[ -n "$green" && "$(jq -r .id <<< "$green")" == "$live_id" ]]; then
  active=green; candidate=blue; live="$green"; stale="$blue"
else
  echo 'Reserved IP is not assigned to a managed sandbox slot; refusing deployment.' >&2
  exit 1
fi

export TF_VAR_deployment_requested_size="${TF_VAR_droplet_size:?TF_VAR_droplet_size must be set}"
export TF_VAR_sandbox_active_slot="$active"
if [[ -n "$stale" ]]; then
  export TF_VAR_sandbox_slots='["blue","green"]'
else
  export TF_VAR_sandbox_slots="[\"$active\"]"
fi
plan_file="$(mktemp)"
chmod 600 "$plan_file"
trap 'rm -f "$plan_file"' EXIT
retire_slot() {
  local retiring="$1" keep="$2" address="${module}.digitalocean_droplet.this[\"$1\"]"
  export TF_VAR_sandbox_active_slot="$keep"
  export TF_VAR_sandbox_slots="[\"$keep\"]"
  terraform plan -lock-timeout=5m -target="$address" -out="$plan_file" >/dev/null || return 1
  if ! terraform show -json "$plan_file" | jq -e --arg address "$address" '
    [.resource_changes[]? | select(.change.actions != ["no-op"]) |
      select(.address != $address or .change.actions != ["delete"])] | length == 0
  ' >/dev/null; then
    echo "Refusing cleanup: the plan changes resources other than the ${retiring} VM." >&2
    return 1
  fi
  [[ "$(assigned_id)" == "$3" ]] || { echo "Reserved IP changed; refusing cleanup." >&2; return 1; }
  terraform apply -lock-timeout=5m "$plan_file"
}
if [[ "$action" == "apply" && -n "$stale" ]]; then
  : "${PACKER_SSH_KEY:?PACKER_SSH_KEY must contain the sandbox SSH private key}"
  stale_ip="$(jq -r '.ipv4_address // empty' <<< "$stale")"
  if [[ -n "$stale_ip" ]]; then ci/dump-logs.sh "$stale_ip" || true; fi
  retire_slot "$candidate" "$active" "$live_id"
  stale=""
fi
terraform plan -lock-timeout=5m -no-color -out="$plan_file"
desired_hash="$(terraform show -json "$plan_file" | jq -er '.planned_values.outputs.deployment_hash.value')"
live_hash="$(jq -r '[.tags[]? | select(startswith("deployment-"))][0] // ""' <<< "$live")"
if [[ "$live_hash" == "deployment-${desired_hash}" ]]; then
  echo 'Live VM matches the desired deployment configuration.'
  if [[ "$action" == "apply" ]]; then
    if [[ -z "${GITHUB_ACTION:-}" ]]; then
      read -r -p 'Apply the plan above? Type yes to continue: ' answer
      [[ "$answer" == yes ]] || exit 1
    fi
    terraform apply -lock-timeout=5m "$plan_file"
  fi
  exit
fi
echo "The live VM differs from the desired deployment; ${candidate} will be created and validated before cutover."
if [[ "$action" == "plan" ]]; then exit; fi
: "${PACKER_SSH_KEY:?PACKER_SSH_KEY must contain the sandbox SSH private key}"
key_file="$(mktemp)"
cert_file="$(mktemp)"
apply_log="$(mktemp)"
chmod 600 "$key_file" "$cert_file" "$apply_log"
printf '%s\n' "$PACKER_SSH_KEY" > "$key_file"
cleanup() {
  status=$?
  trap - EXIT
  if [[ "$status" -ne 0 && "${candidate_started:-false}" == true ]]; then
    current_id="$(assigned_id 2>/dev/null || true)"
    if [[ "$current_id" == "$live_id" ]]; then
      if [[ -z "${new_ip:-}" ]]; then
        state="$(terraform state pull 2>/dev/null || true)"
        new_ip="$(resource "$slot_address" 2>/dev/null | jq -r '.ipv4_address // empty' 2>/dev/null || true)"
      fi
      if [[ -n "${new_ip:-}" ]]; then ci/dump-logs.sh "$new_ip" || true; fi
      retire_slot "$candidate" "$active" "$live_id" || echo 'Candidate cleanup failed; check the reserved IP and remove the inactive VM.' >&2
    elif [[ -n "${new_id:-}" && "$current_id" == "$new_id" ]]; then
      if [[ -n "${new_ip:-}" ]]; then ci/dump-logs.sh "$new_ip" || true; fi
      ci/dump-logs.sh "$live_ip" || true
      retire_slot "$active" "$candidate" "$new_id" || echo 'Old VM cleanup failed; check the reserved IP and remove the inactive VM.' >&2
    else
      echo 'Cannot identify the reserved IP owner; retaining both VMs to avoid deleting the live VM.' >&2
    fi
  fi
  rm -f "$key_file" "$cert_file" "$plan_file" "$apply_log"
  exit "$status"
}
trap cleanup EXIT
ssh_args=(-i "$key_file" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=2)
live_ssh_args=("${ssh_args[@]}")
live_ip="$(jq -er .ipv4_address <<< "$live")"
echo 'Checking that PACKER_SSH_KEY can access the live sandbox.'
if ! ssh "${ssh_args[@]}" "core@${live_ip}" 'true'; then
  echo 'PACKER_SSH_KEY could not access the live sandbox; trying the default SSH identity.' >&2
  live_ssh_args=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=10 -o ServerAliveCountMax=2)
  if ! ssh "${live_ssh_args[@]}" "core@${live_ip}" 'true'; then
    echo 'Neither PACKER_SSH_KEY nor the default SSH identity can access the live sandbox.' >&2
    exit 1
  fi
fi
echo 'Checking the live ACME certificate before creating a candidate.'
ssh "${live_ssh_args[@]}" "core@${live_ip}" 'sudo cat /opt/sandbox/acme/acme.json' > "$cert_file"
python3 ci/check-acme.py "$cert_file" "$SANDBOX_DOMAIN" "fcrepo.${SANDBOX_DOMAIN}"
export TF_VAR_sandbox_slots='["blue","green"]'
export TF_VAR_sandbox_active_slot="$active"
slot_address="${module}.digitalocean_droplet.this[\"${candidate}\"]"
candidate_started=true
sizes="${TF_VAR_droplet_size} ${DIGITALOCEAN_FALLBACK_SIZES-s-4vcpu-8gb}"
created=false
seen_sizes=' '
for size in $sizes; do
  case "$seen_sizes" in *" $size "*) continue ;; esac
  seen_sizes="${seen_sizes}${size} "
  export TF_VAR_droplet_size="$size"
  echo "Creating ${candidate} with size ${size} in ${TF_VAR_region}."
  if [[ -n "${GITHUB_ACTION:-}" ]]; then
    if terraform apply -no-color -lock-timeout=5m -auto-approve -target="$slot_address" 2>&1 | tee "$apply_log"; then created=true; break; fi
  else
    if terraform apply -no-color -lock-timeout=5m -target="$slot_address" 2>&1 | tee "$apply_log"; then created=true; break; fi
  fi
  if ! grep -Fq '422' "$apply_log" || ! grep -Fq 'Size is not available in this region' "$apply_log"; then
    echo 'Candidate creation failed; not retrying with a different size.' >&2
    exit 1
  fi
  state="$(terraform state pull)"
  if resource "$slot_address" >/dev/null 2>&1; then
    echo 'Candidate is present in state after the failure; refusing to retry.' >&2
    exit 1
  fi
  echo "Size ${size} is unavailable in ${TF_VAR_region}; checking the next fallback." >&2
done
if [[ "$created" != true ]]; then
  echo "No configured droplet size is available in ${TF_VAR_region}; the live sandbox remains unchanged." >&2
  exit 1
fi
state="$(terraform state pull)"
new="$(resource "$slot_address")"
new_ip="$(jq -er .ipv4_address <<< "$new")"
new_id="$(jq -er .id <<< "$new")"

# The template checks HTTPS during bootstrap, so install the live certificate
# before waiting for demo-object creation.
bootstrap_started=$SECONDS
bootstrap_timeout="${BOOTSTRAP_TIMEOUT_SECONDS:-3600}"
deadline=$((bootstrap_started + bootstrap_timeout))
echo "Waiting up to ${bootstrap_timeout}s for SSH and bootstrap on ${candidate} (${new_ip})."
until ssh "${ssh_args[@]}" "core@${new_ip}" 'true' 2>/dev/null; do
  if (( SECONDS >= deadline )); then
    echo 'Candidate SSH timed out; live sandbox remains unchanged.' >&2
    exit 1
  fi
  echo "${candidate} SSH is not ready yet ($((SECONDS - bootstrap_started))s elapsed); checking again in 15s."
  sleep 15
done
echo 'Copying the live ACME store to the candidate.'
ssh "${ssh_args[@]}" "core@${new_ip}" \
  'sudo mkdir -p /opt/sandbox/acme && sudo install -m 600 /dev/stdin /opt/sandbox/acme/acme.json' < "$cert_file"
local_acme_hash="$(python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())' "$cert_file")"
remote_acme_hash="$(ssh "${ssh_args[@]}" "core@${new_ip}" 'sudo sha256sum /opt/sandbox/acme/acme.json' | awk '{print $1}')"
if [[ "$local_acme_hash" != "$remote_acme_hash" ]]; then
  echo 'ACME store changed during transfer; refusing to start the candidate.' >&2
  exit 1
fi
ssh "${ssh_args[@]}" "core@${new_ip}" 'sudo touch /opt/sandbox/acme/.ready'

# Bootstrap creates demo objects before writing this marker.
echo "Waiting for ${candidate} to finish bootstrap and demo-object creation."
while true; do
  if bootstrap_status="$(ssh "${ssh_args[@]}" "core@${new_ip}" \
    'if test -f /opt/sandbox/.bootstrapped; then echo ready; else systemctl show sandbox-bootstrap.service -p LoadState -p ActiveState -p SubState -p Result; fi' 2>&1)"; then
    if [[ "$bootstrap_status" == "ready" ]]; then break; fi
  else
    echo "Could not check ${candidate} bootstrap over SSH: ${bootstrap_status}" >&2
  fi
  if [[ "$bootstrap_status" == *'ActiveState=failed'* ]]; then
    echo 'Candidate bootstrap failed; collecting logs and cleaning up.' >&2
    exit 1
  fi
  if (( SECONDS >= deadline )); then
    echo 'Candidate bootstrap timed out; live sandbox remains unchanged.' >&2
    exit 1
  fi
  echo "${candidate} bootstrap is not ready yet ($((SECONDS - bootstrap_started))s elapsed); ${bootstrap_status//$'\n'/, }; checking again in 15s."
  sleep 15
done
echo "${candidate} bootstrap completed after $((SECONDS - bootstrap_started))s."

HEALTH_CHECK_IP="$new_ip" ci/health-check.sh "https://${SANDBOX_DOMAIN}"
[[ "$(assigned_id)" == "$live_id" ]] || { echo 'Reserved IP changed during deployment.' >&2; exit 1; }

export TF_VAR_sandbox_active_slot="$candidate"
terraform plan -lock-timeout=5m -out="$plan_file"
if ! terraform show -json "$plan_file" | jq -e --arg module "$module" '
  [.resource_changes[]? | select(.change.actions != ["no-op"]) |
    select(.address == ($module + ".digitalocean_reserved_ip.this") or
           (.address | startswith($module + ".digitalocean_droplet.this[")))] | length == 0
' >/dev/null; then
  echo 'Refusing cutover: the plan changes a droplet or the reserved IP itself.' >&2
  exit 1
fi
if [[ -z "${GITHUB_ACTION:-}" ]]; then
  read -r -p 'Apply the cutover plan above? Type yes to continue: ' answer
  [[ "$answer" == yes ]] || exit 1
fi
terraform apply -lock-timeout=5m "$plan_file"
[[ "$(assigned_id)" == "$new_id" ]] || { echo 'Reserved IP cutover did not complete.' >&2; exit 1; }
ci/health-check.sh "https://${SANDBOX_DOMAIN}"
retire_slot "$active" "$candidate" "$new_id"

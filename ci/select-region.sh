#!/usr/bin/env bash
set -euo pipefail

size="${1:-${TF_VAR_droplet_size:-s-4vcpu-8gb-amd}}"
candidate_regions="${DIGITALOCEAN_CANDIDATE_REGIONS:-tor1 nyc3 sfo3}"

if [[ -z "${DIGITALOCEAN_TOKEN:-}" ]]; then
  echo "DIGITALOCEAN_TOKEN is required to select a deployment region" >&2
  exit 1
fi

sizes_json="$(curl -fsS \
  -H "Authorization: Bearer ${DIGITALOCEAN_TOKEN}" \
  -H "Content-Type: application/json" \
  "https://api.digitalocean.com/v2/sizes?per_page=200")"

for region in $candidate_regions; do
  if jq -e --arg size "$size" --arg region "$region" '
    .sizes[]
    | select(.slug == $size and .available == true)
    | .regions
    | index($region)
  ' >/dev/null <<< "$sizes_json"; then
    echo "$region"
    exit 0
  fi
done

echo "No available DigitalOcean region found for size ${size}. Checked: ${candidate_regions}" >&2
exit 1

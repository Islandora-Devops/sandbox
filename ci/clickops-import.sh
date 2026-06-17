#!/usr/bin/env bash

set -euo pipefail

# terraform import evaluates the full config, so required variables still need
# values even when they are not part of the imported resource.
export TF_VAR_isle_password="${TF_VAR_isle_password:-placeholder}"

: "${DIGITALOCEAN_TOKEN:?DIGITALOCEAN_TOKEN must be set}"
: "${AWS_ACCESS_KEY_ID:?AWS_ACCESS_KEY_ID must be set}"
: "${AWS_SECRET_ACCESS_KEY:?AWS_SECRET_ACCESS_KEY must be set}"
export SPACES_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
export SPACES_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"

sandbox_ip="${SANDBOX_RESERVED_IP:-159.203.49.92}"
test_ip="${TEST_RESERVED_IP:-174.138.112.33}"

select_workspace() {
  local workspace="$1"
  terraform workspace select "$workspace" >/dev/null 2>&1 || terraform workspace new "$workspace" >/dev/null
}

rid() {
  local records="$1" type="$2" name="$3"
  echo "$records" | jq -r --arg t "$type" --arg n "$name" \
    '.[] | select(.type == $t and .name == $n) | .id'
}

rid_data() {
  local records="$1" type="$2" name="$3" data="$4"
  echo "$records" | jq -r --arg t "$type" --arg n "$name" --arg d "$data" \
    'def trimdot: sub("\\.$"; "");
    .[]
    | select(.type == $t and .name == $n)
    | select((.data // "") == $d or ((.data // "") | trimdot) == ($d | trimdot))
    | .id'
}

image_id_by_name() {
  local name="$1"
  doctl compute image list --output json | jq -r --arg name "$name" '.[] | select(.name == $name) | .id' | head -n1
}

droplet_id_by_name() {
  local name="$1"
  doctl compute droplet list --output json | jq -r --arg name "$name" '.[] | select(.name == $name) | .id' | head -n1
}

import_if_present() {
  local address="$1" id="$2"
  if terraform state show "$address" >/dev/null 2>&1; then
    echo "Skipping $address: already managed in state"
    return
  fi
  if [[ -n "$id" && "$id" != "null" && "$id" != *",null" && "$id" != *"," ]]; then
    terraform import "$address" "$id"
  else
    echo "Skipping $address: import id not found" >&2
  fi
}

echo "Fetching domain records..."
islandora_records="$(doctl compute domain records list islandora.ca --output json)"
sandbox_records="$(doctl compute domain records list sandbox.islandora.ca --output json)"
test_records="$(doctl compute domain records list test.islandora.ca --output json)"

echo "Importing sandbox workspace resources..."
select_workspace sandbox

sandbox_image_name="${SANDBOX_COREOS_IMAGE_NAME:-fedora-coreos-43.20260217.3.1-sandbox-${TF_VAR_region:-tor1}}"
sandbox_image_id="$(image_id_by_name "$sandbox_image_name")"
sandbox_droplet_id="$(droplet_id_by_name sandbox)"

import_if_present 'digitalocean_spaces_bucket.terraform_state[0]' 'tor1,sandbox-terraform-state'
import_if_present 'digitalocean_custom_image.coreos[0]' "$sandbox_image_id"
import_if_present 'module.environment["sandbox"].digitalocean_domain.this' 'sandbox.islandora.ca'
import_if_present 'module.environment["sandbox"].digitalocean_reserved_ip.this' "$sandbox_ip"
import_if_present 'module.environment["sandbox"].digitalocean_record.root_a' "sandbox.islandora.ca,$(rid "$sandbox_records" A @)"
import_if_present 'module.environment["sandbox"].digitalocean_record.wildcard_cname' "sandbox.islandora.ca,$(rid "$sandbox_records" CNAME '*')"
import_if_present 'module.environment["sandbox"].digitalocean_droplet.this' "$sandbox_droplet_id"
import_if_present 'module.environment["sandbox"].digitalocean_reserved_ip_assignment.this' "${sandbox_ip},${sandbox_droplet_id}"

import_if_present 'digitalocean_domain.islandora_ca[0]' 'islandora.ca'
import_if_present 'digitalocean_record.islandora_ca_a["@"]' "islandora.ca,$(rid "$islandora_records" A @)"
import_if_present 'digitalocean_record.islandora_ca_a["dev"]' "islandora.ca,$(rid "$islandora_records" A dev)"
import_if_present 'digitalocean_record.islandora_ca_a["automate"]' "islandora.ca,$(rid "$islandora_records" A automate)"
import_if_present 'digitalocean_record.islandora_ca_a["webmail"]' "islandora.ca,$(rid "$islandora_records" A webmail)"
import_if_present 'digitalocean_record.islandora_ca_a["legacy"]' "islandora.ca,$(rid "$islandora_records" A legacy)"
import_if_present 'digitalocean_record.islandora_ca_a["ftp"]' "islandora.ca,$(rid "$islandora_records" A ftp)"
import_if_present 'digitalocean_record.islandora_ca_sandbox_a["fcrepo"]' "islandora.ca,$(rid "$islandora_records" A fcrepo)"
import_if_present 'digitalocean_record.islandora_ca_sandbox_a["sandbox"]' "islandora.ca,$(rid "$islandora_records" A sandbox)"
import_if_present 'digitalocean_record.islandora_ca_cname["www"]' "islandora.ca,$(rid "$islandora_records" CNAME www)"
import_if_present 'digitalocean_record.islandora_ca_cname["2025"]' "islandora.ca,$(rid "$islandora_records" CNAME 2025)"
import_if_present 'digitalocean_record.islandora_ca_cname["*.automate"]' "islandora.ca,$(rid "$islandora_records" CNAME '*.automate')"
import_if_present 'digitalocean_record.islandora_ca_cname["mail"]' "islandora.ca,$(rid "$islandora_records" CNAME mail)"
import_if_present 'digitalocean_record.islandora_ca_cname["*.sandbox"]' "islandora.ca,$(rid "$islandora_records" CNAME '*.sandbox')"
import_if_present 'digitalocean_record.islandora_ca_ns_sandbox["ns1.digitalocean.com."]' "islandora.ca,$(rid_data "$islandora_records" NS sandbox ns1.digitalocean.com.)"
import_if_present 'digitalocean_record.islandora_ca_ns_sandbox["ns2.digitalocean.com."]' "islandora.ca,$(rid_data "$islandora_records" NS sandbox ns2.digitalocean.com.)"
import_if_present 'digitalocean_record.islandora_ca_ns_sandbox["ns3.digitalocean.com."]' "islandora.ca,$(rid_data "$islandora_records" NS sandbox ns3.digitalocean.com.)"
import_if_present 'digitalocean_record.islandora_ca_ns_test["ns1.digitalocean.com."]' "islandora.ca,$(rid_data "$islandora_records" NS test ns1.digitalocean.com.)"
import_if_present 'digitalocean_record.islandora_ca_ns_test["ns2.digitalocean.com."]' "islandora.ca,$(rid_data "$islandora_records" NS test ns2.digitalocean.com.)"
import_if_present 'digitalocean_record.islandora_ca_ns_test["ns3.digitalocean.com."]' "islandora.ca,$(rid_data "$islandora_records" NS test ns3.digitalocean.com.)"
import_if_present 'digitalocean_record.islandora_ca_mx["aspmx.l.google.com."]' "islandora.ca,$(rid_data "$islandora_records" MX @ aspmx.l.google.com.)"
import_if_present 'digitalocean_record.islandora_ca_mx["alt1.aspmx.l.google.com."]' "islandora.ca,$(rid_data "$islandora_records" MX @ alt1.aspmx.l.google.com.)"
import_if_present 'digitalocean_record.islandora_ca_mx["alt2.aspmx.l.google.com."]' "islandora.ca,$(rid_data "$islandora_records" MX @ alt2.aspmx.l.google.com.)"
import_if_present 'digitalocean_record.islandora_ca_mx["alt3.aspmx.l.google.com."]' "islandora.ca,$(rid_data "$islandora_records" MX @ alt3.aspmx.l.google.com.)"
import_if_present 'digitalocean_record.islandora_ca_mx["alt4.aspmx.l.google.com."]' "islandora.ca,$(rid_data "$islandora_records" MX @ alt4.aspmx.l.google.com.)"
import_if_present 'digitalocean_record.islandora_ca_txt_github_pages_challenge[0]' "islandora.ca,$(rid "$islandora_records" TXT _github-pages-challenge-islandora-community)"
import_if_present 'digitalocean_record.islandora_ca_txt_dkim_google[0]' "islandora.ca,$(rid "$islandora_records" TXT google._domainkey)"
import_if_present 'digitalocean_record.islandora_ca_txt_domainkey[0]' "islandora.ca,$(rid "$islandora_records" TXT _domainkey)"
import_if_present 'digitalocean_record.islandora_ca_txt_google_verify[0]' "islandora.ca,$(rid_data "$islandora_records" TXT @ 'google-site-verification=WC57eo9SoIqzU8qHIOhZuEcS-Wj5WTvDju-accRLNCY')"
import_if_present 'digitalocean_record.islandora_ca_txt_spf[0]' "islandora.ca,$(rid_data "$islandora_records" TXT @ 'v=spf1 +a +mx +a:us170.siteground.us include:_spf.mailspamprotection.com ~all')"

echo "Importing test workspace resources..."
select_workspace test

test_image_name="${TEST_COREOS_IMAGE_NAME:-fedora-coreos-43.20260217.3.1-test-${TF_VAR_region:-tor1}}"
test_image_id="$(image_id_by_name "$test_image_name")"
test_droplet_id="$(droplet_id_by_name test)"

import_if_present 'digitalocean_custom_image.coreos[0]' "$test_image_id"
import_if_present 'module.environment["test"].digitalocean_domain.this' 'test.islandora.ca'
import_if_present 'module.environment["test"].digitalocean_reserved_ip.this' "$test_ip"
import_if_present 'module.environment["test"].digitalocean_record.root_a' "test.islandora.ca,$(rid "$test_records" A @)"
import_if_present 'module.environment["test"].digitalocean_record.wildcard_cname' "test.islandora.ca,$(rid "$test_records" CNAME '*')"
import_if_present 'module.environment["test"].digitalocean_droplet.this' "$test_droplet_id"
import_if_present 'module.environment["test"].digitalocean_reserved_ip_assignment.this' "${test_ip},${test_droplet_id}"

echo "Imports complete."

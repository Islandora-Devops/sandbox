# Islandora Sandbox <!-- omit in toc -->

[![LICENSE](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](./LICENSE)

## Table of Contents <!-- omit in toc -->
- [Introduction](#introduction)
- [Requirements](#requirements)
- [Remote State](#remote-state)
- [Provisioning](#provisioning)
- [CI/CD Workflow](#cicd-workflow)
- [Local Debugging](#local-debugging)
- [Nightly Refresh](#nightly-refresh)
- [Domains](#domains)

## Introduction

This repository is an example of how to deploy ISLE to a cloud provider using
infrastructure as code. In this implementation, the target cloud provider is
[DigitalOcean], Terraform manages the cloud resources, [cloud-compose] provides
the reusable VM/app runtime, and [islandora-devops/isle-site-template] provides the Islandora
application stack.

The repository keeps the sandbox-specific pieces small: delegated DNS zones,
reserved IPs, environment defaults, and the nightly demo-content refresh.
cloud-compose owns the droplet, persistent volumes, Docker runtime, sitectl
context, ingress component configuration, application deploy, and healthcheck
lifecycle.

For the live Islandora sandbox, provisioned VMs clone
`https://github.com/islandora-devops/isle-site-template` from the `main` branch by default. The
Terraform root is workspace-driven:

- `test` manages the review environment at `test.islandora.ca`
- `sandbox` manages the long-lived environment at `sandbox.islandora.ca`

The shared parent `islandora.ca` zone remains managed from the `sandbox`
workspace so there is only one writer for the shared DNS records.

## Requirements

- A [DigitalOcean] account
- A Spaces bucket for Terraform state
- A Spaces access key and secret key
- Terraform 1.11+
- `jq`
- Chrome or Chromium for health checks and review screenshots

For local health checks, `ci/health-check.sh` looks for `google-chrome`,
`google-chrome-stable`, `chromium`, `chromium-browser`, and the standard macOS
Google Chrome app path. Set `HEALTH_CHECK_BROWSER` if Chrome is installed
somewhere else. The browser load keeps JavaScript alive for 12 seconds by
default so captcha-protect can autosubmit its challenge before the node checks
run; override that with `HEALTH_CHECK_CHALLENGE_WAIT_SECONDS` if needed.

## Remote State

This repository follows DigitalOcean's guide, [How to Use DigitalOcean Spaces as a Terraform Remote State Backend](https://docs.digitalocean.com/products/spaces/reference/terraform-backend/).

Important details from that guide that this repository follows:

- The Spaces bucket must exist before `terraform init` uses the remote backend.
- The bucket is declared in the no-backend [bootstrap](./bootstrap) Terraform root and can be created locally with `make bootstrap-state`.
- The backend uses the `s3` backend type with the DigitalOcean Spaces endpoint.
- Credentials are passed with `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`, not Terraform variables.
- `use_lockfile = true` is enabled for state locking.
- AWS-specific checks are disabled with the documented `skip_*` flags and `region = "us-east-1"`.

The backend configuration in [main.tf](./main.tf) is:

```hcl
backend "s3" {
  endpoints = {
    s3 = "https://tor1.digitaloceanspaces.com"
  }

  bucket = "sandbox-terraform-state"
  key    = "terraform.tfstate"

  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_s3_checksum            = true
  region                      = "us-east-1"
  use_lockfile                = true
}
```

## Provisioning

Provisioning is intentionally script-driven so local runs and GitHub Actions use
exactly the same entry points:

- [Makefile](./Makefile) provides the public commands.
- [ci/deploy-local.sh](./ci/deploy-local.sh) is the shared Terraform runner used by local operators and GitHub Actions.
- [ci/select-region.sh](./ci/select-region.sh) chooses the first candidate DigitalOcean region where the requested droplet size is currently available.
- [ci/screenshot.sh](./ci/screenshot.sh) captures the review screenshot.
- [ci/fetch-json.sh](./ci/fetch-json.sh) fetches and pretty-prints the JSON-LD check used in the PR comment.
- [ci/health-check.sh](./ci/health-check.sh) and [ci/check-nodes.sh](./ci/check-nodes.sh) validate that the expected Drupal nodes exist before a deployment is considered healthy.
- [main.tf](./main.tf) consumes [cloud-compose] `0.10.0` through the DigitalOcean provider entrypoint; cloud-compose manages the droplet, persistent volumes, firewall, Docker, Docker Compose, sitectl, and application lifecycle.
- [modules/environment](./modules/environment) keeps the delegated DNS zone, wildcard/root records, reserved IP, and reserved-IP assignment stable around the cloud-compose droplet.

The main local provisioning commands are:

```bash
make tf-test ACTION=plan
make tf-test ACTION=apply
make tf-prod ACTION=plan
make tf-prod ACTION=apply
make tf-test ACTION=cleanup
```

`make tf-test ACTION=cleanup` is the normal teardown path for test runs. It
destroys only ephemeral test compute resources and keeps the `test.islandora.ca`
DNS zone and reserved IP in Terraform state.

Run local checks before opening or updating a PR:

```bash
make lint
```

This checks Terraform formatting, validates the main and bootstrap Terraform
roots, and runs ShellCheck against all `*.sh` scripts.

`ACTION` defaults to `plan`, so `make tf-test` and `make tf-prod` are shorthand
for planning the test and production workspaces. The deploy script initializes
the remote Spaces backend, selects the Terraform workspace, selects an available
DigitalOcean region for test unless `TF_VAR_region` is already set, pins
production to `SANDBOX_REGION` or `tor1` by default, validates Terraform for
non-destroy actions, and then runs the requested Terraform action.
Terraform reads the base environment from [.env](./.env) and passes
workspace-specific `DOMAIN`, `TAG`, and `COMPOSE_PROJECT_NAME` values into the
cloud-compose runtime. During VM bootstrap, cloud-compose installs host
dependencies, clones [islandora-devops/isle-site-template], configures the sitectl context, enables
Let's Encrypt and bot mitigation through sitectl ingress settings, writes the
ISLE admin secret files, then runs `make init build demo-objects` and
`sitectl healthcheck`.

The default droplet size is `s-4vcpu-8gb-amd`, matching the imported sandbox
droplet. Override it with `TF_VAR_droplet_size` if DigitalOcean capacity requires
a different slug.

The site repository and branch can be overridden with Terraform variables, but
the defaults should normally be used:

```bash
TF_VAR_repo_url=https://github.com/islandora-devops/isle-site-template
TF_VAR_repo_branch=main
```

## CI/CD Workflow

The GitHub workflows also go through the same `make` and `ci/*.sh` paths:

- Pull requests run plans for both workspaces in [terraform-plan.yml](./.github/workflows/terraform-plan.yml), post or update a sticky PR comment, deploy `test.islandora.ca`, run the health checks, upload review artifacts, and then run test cleanup with `if: always()`.
- Pushes to `main` and manual workflow dispatches run [terraform-apply.yml](./.github/workflows/terraform-apply.yml), which deploys and validates only `sandbox.islandora.ca`.
- Test cleanup destroys only ephemeral cloud-compose test compute resources and the reserved IP assignment. The `test.islandora.ca` DNS zone and reserved IP remain managed in Terraform state.
- The PR and sandbox deploy workflows share the same concurrency group with `cancel-in-progress: false` so test cleanup is not skipped by a newer push.

## Local Debugging

Local debugging follows the same path as CI. Export these local environment
variables:

```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export DIGITALOCEAN_TOKEN="..."
export ISLE_PASSWORD="..."

make tf-test ACTION=apply
make tf-prod ACTION=apply
make tf-test ACTION=cleanup
```

Use the `make tf-*` targets for local operator work instead of raw Terraform
commands. The targets supply the same environment, region selection, validation,
and health-check behavior used in GitHub Actions.

If you only want a single operation, use the narrower targets:

```bash
make tf-test ACTION=plan
make tf-prod ACTION=plan
make tf-test ACTION=apply
make tf-prod ACTION=apply
make tf-test ACTION=cleanup
```

`make tf-test ACTION=destroy` is guarded because it removes the entire test
workspace, including `test.islandora.ca` DNS and the test reserved IP. Use
`make destroy-test` only when intentionally removing those shared resources.

## Nightly Refresh

The sandbox application/data state is refreshed nightly inside the VM by
systemd. This is not a Terraform droplet recreation.

- [rake.timer](./rootfs/etc/systemd/system/rake.timer) runs every day at
  `03:15 America/Toronto`, with a 30 minute randomized delay.
- [rake.service](./rootfs/etc/systemd/system/rake.service) runs as the
  `cloud-compose` user and calls [rake.sh](./rootfs/home/cloud-compose/rake.sh).
- [rake.sh](./rootfs/home/cloud-compose/rake.sh) resolves the primary app from
  the cloud-compose app manifest, runs `docker compose down -v`, reruns
  `make demo-objects`, and finishes with `sitectl healthcheck`.

The result is a nightly reset of the ISLE demo content and containers while the
DigitalOcean droplet, reserved IP, DNS records, and Terraform state remain
managed by Terraform.

## Domains

The delegated `test.islandora.ca` and `sandbox.islandora.ca` zones are managed
by the shared environment module in [modules/environment/main.tf](./modules/environment/main.tf).
The parent `islandora.ca` records live in [dns-islandora-ca.tf](./dns-islandora-ca.tf).
DNS records for these zones should be changed in Terraform and reviewed through
pull requests, not edited directly in the DigitalOcean UI. If an emergency
clickops change is made in DigitalOcean, import or reconcile it in Terraform
before the next apply so Terraform remains the source of truth.

## Bootstrapping

Existing DigitalOcean resources were brought under Terraform management with
[ci/clickops-import.sh](./ci/clickops-import.sh). The script imports resources into both
Terraform workspaces:

- `sandbox` imports `sandbox.islandora.ca`, the production reserved IP, the
  droplet named `sandbox`, sandbox DNS records, shared `islandora.ca` DNS
  records, and the `sandbox-terraform-state` Spaces bucket.
- `test` imports `test.islandora.ca`, the test reserved IP, the droplet named
  `test` if present, and test DNS records.

The shared parent `islandora.ca` zone is imported only in the `sandbox`
workspace because that workspace is the only Terraform writer for shared DNS.

Before importing, create GitHub Actions repository secrets:

- `DIGITALOCEAN_API_TOKEN`
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `ISLE_PASSWORD`

GitHub Actions maps `DIGITALOCEAN_API_TOKEN` to the runtime
`DIGITALOCEAN_TOKEN` environment variable used by Terraform and helper scripts.
For local bootstrapping, export the runtime variable names directly and create
the remote state bucket with the no-backend bootstrap root:

```bash
export DIGITALOCEAN_TOKEN="..."
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."

doctl auth init
doctl account get

make bootstrap-state
make init
```

`make bootstrap-state` runs Terraform from the no-backend
[bootstrap](./bootstrap) Terraform root and creates only the
`sandbox-terraform-state` Spaces bucket, because the main remote backend bucket
cannot be used until it exists. After this step, initialize the main Terraform
root with `make init`. The make/script entrypoints set `TF_DATA_DIR` under
`/tmp` because Terraform's Git downloader can mis-handle module refs when the
data directory is inside this repository.

After the backend is initialized, run the import script so existing resources
are written to remote state:

```bash
./ci/clickops-import.sh
```

`ci/clickops-import.sh` initializes Terraform, then skips resources already
present in state, so it is safe for the state bucket to have been created by
`make bootstrap-state` before the import.

The script defaults to the existing reserved IPs:

```bash
SANDBOX_RESERVED_IP=159.203.49.92
TEST_RESERVED_IP=174.138.112.33
```

Override them when running the import if DigitalOcean has different addresses:

```bash
SANDBOX_RESERVED_IP="..." TEST_RESERVED_IP="..." ./ci/clickops-import.sh
```

After importing, verify drift in both workspaces before applying:

```bash
make plan-prod
make plan-test
```

[DigitalOcean]: https://www.digitalocean.com/
[cloud-compose]: https://cc.libops.io/
[islandora-devops/isle-site-template]: https://github.com/islandora-devops/isle-site-template

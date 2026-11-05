# Islandora Sandbox <!-- omit in toc -->

[![LICENSE](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](./LICENSE)

## Table of Contents <!-- omit in toc -->
- [Introduction](#introduction)
- [Requirements](#requirements)
- [Remote State](#remote-state)
- [Provisioning](#provisioning)
- [CI/CD Workflow](#cicd-workflow)
- [Local Debugging](#local-debugging)
- [Sandbox Maintenance](#sandbox-maintenance)
- [Domains](#domains)

## Introduction

This repository is an example of how to deploy ISLE to a cloud provider using
infrastructure as code. In this implementation, the target cloud provider is
[DigitalOcean], Terraform manages the cloud resources, [Fedora CoreOS] runs the
host, and [isle-site-template] provides the Islandora application stack.

The same pattern can be adapted to other providers: define the cloud primitives
in Terraform, bootstrap the VM with the ISLE site template, validate expected
Islandora content after deployment.

For the live Islandora sandbox, provisioned VMs clone
`https://github.com/Islandora-Devops/isle-site-template` from the `main` branch
by default. The Terraform root uses the `sandbox` workspace for the live
sandbox and shared parent DNS records.

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
- [ci/health-check.sh](./ci/health-check.sh) and [ci/check-nodes.sh](./ci/check-nodes.sh) validate that the expected Drupal nodes exist before a deployment is considered healthy.
- [main.tf](./main.tf) manages the Fedora CoreOS image in the sandbox workspace.

The main local provisioning commands are:

```bash
make tf-prod ACTION=plan
make tf-prod ACTION=apply
```

When the deployment configuration changes, apply creates the inactive blue or green VM, waits for bootstrap, copies the
live Traefik ACME store, and validates required nodes through the candidate's
own IP. It then moves the reserved IP, validates the live endpoint, and removes
the old VM. Set `PACKER_SSH_KEY` to the private key used for new VMs. If that
key cannot access the live VM, deployment retries with the default SSH identity.
Deployments add its public key and the public keys published by the GitHub
accounts in the [Islandora committer list](https://islandora.github.io/documentation/contributing/committers/#committers)
to new VMs. The list and keys are fetched for each plan and apply.
Candidate bootstrap has a separate one-hour timeout, configurable with
`BOOTSTRAP_TIMEOUT_SECONDS`.
On failure, the deploy captures available logs and attempts to remove the inactive VM. If the reserved IP owner cannot be identified or cleanup fails, inspect the VMs and retry cleanup.

Run local checks before opening or updating a PR:

```bash
make lint
```

This checks Terraform formatting, validates the main and bootstrap Terraform
roots, and runs ShellCheck against all `*.sh` scripts.

`ACTION` defaults to `plan`. The deploy script initializes the remote Spaces
backend, selects the sandbox workspace, uses `TF_VAR_region`, `SANDBOX_REGION`,
or `tor1`, validates Terraform, and runs the requested action.
Terraform reads the base environment from [.env](./.env) and writes
workspace-specific `DOMAIN` and `TAG` values into the VM Ignition payload.
During VM bootstrap, [rootfs/opt/sandbox/setup.sh](./rootfs/opt/sandbox/setup.sh)
installs the required host tools, clones [isle-site-template] and `libops/captcha-protect` at the pinned release
in `setup.sh`, copies `compose.override.yaml`, the generated `.env`, and secrets, then runs
`make init build demo-objects` (which runs `make up`). The Compose override
configures Let's Encrypt, persists ACME certificates in `/opt/sandbox/acme`, and
mounts captcha-protect as a local Traefik plugin. Drupal, IIIF (Cantaloupe), and Fedora use child routers behind one HTTPS
parent with a shared proof-of-javascript middleware instance. The file-provider
configs replace the template routers, preserve their path rewrites, and use a
challenge secret generated during setup.
Validate the override against a local template checkout with
`ci/check-compose.sh /path/to/isle-site-template`. Run
`ci/check-protected-routing.py /path/to/captcha-protect` with Docker and a
checkout of the pinned plugin to verify that Drupal, IIIF JSON/images, and
Fedora requests all receive the parent challenge.

The default droplet size is `s-4vcpu-8gb-amd`, matching the imported sandbox
droplet. If DigitalOcean reports that size is unavailable in the reserved IP's
region, deployment retries with `s-4vcpu-8gb`. Override the preferred size with
`TF_VAR_droplet_size` and the space-separated fallback list with
`DIGITALOCEAN_FALLBACK_SIZES`. Availability can still change between retries.

The site repository and branch can be overridden with Terraform variables, but
the defaults should normally be used:

```bash
TF_VAR_repo_url=https://github.com/Islandora-Devops/isle-site-template
TF_VAR_repo_branch=main
```

## CI/CD Workflow

The GitHub workflows also go through the same `make` and `ci/*.sh` paths:

- Pull requests plan the sandbox workspace and post the plan in a PR comment.
- Pushes to `main` validate the candidate before applying the sandbox cutover.

## Local Debugging

Export `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `DIGITALOCEAN_TOKEN`,
`ISLE_PASSWORD`, and `PACKER_SSH_KEY`, then run `make tf-prod ACTION=plan` or
`make tf-prod ACTION=apply`. The same entry points are used by GitHub Actions.

## Sandbox Maintenance

There is no nightly reset. Renovate dependency updates trigger deployments that
replace the VM; these replacements provide the regular refresh of demo content.
Rebooting the VM preserves Docker volumes and starts the existing containers.

For on-demand recovery, open **Actions → Sandbox Maintenance → Run workflow**
on the default branch and select an operation:

- **reset** runs `docker compose down -v` followed by `make demo-objects` as
  `core` in `/opt/sandbox/isle-site-template`. This deletes all demo data in
  Docker volumes and rebuilds the demo objects. Expect downtime during the reset.
- **reboot** requests a reboot through the DigitalOcean API, so it also works
  when SSH is unresponsive. Completion means the reboot was accepted; allow
  time for the VM and application to start.

The workflow targets only the production sandbox. Reset requires the repository
secret `PACKER_SSH_KEY` containing a private key authorized for `core` on the VM.
Reboot uses the existing `DIGITALOCEAN_API_TOKEN` secret and requires exactly one
DigitalOcean droplet named `sandbox`. Maintenance runs are serialized; avoid
running maintenance during a Terraform deployment. After either operation,
verify the site with `make health-check-prod`.

Removing the timer takes effect when Terraform next replaces the VM. To stop
nightly resets on an existing VM before replacement, run
`sudo systemctl disable --now rake.timer` on that VM.

## Domains

The `sandbox.islandora.ca` zone is managed
by the environment module in [modules/environment/main.tf](./modules/environment/main.tf).
The parent `islandora.ca` records live in [dns-islandora-ca.tf](./dns-islandora-ca.tf).
DNS records for these zones should be changed in Terraform and reviewed through
pull requests, not edited directly in the DigitalOcean UI. If an emergency
clickops change is made in DigitalOcean, import or reconcile it in Terraform
before the next apply so Terraform remains the source of truth.

## Bootstrapping

Existing DigitalOcean resources can be brought under Terraform management with
[ci/clickops-import.sh](./ci/clickops-import.sh) in the sandbox workspace.
Terraform moves the original droplet state into the blue slot automatically.

The former test workspace is no longer used by deployment. Its existing resources
and remote state are not deleted by this change; inspect and retire them
separately when appropriate. If the image was already moved to test state by an
intermediate deployment, migrate its state ownership before applying sandbox;
do not manage the same image in two states.

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
terraform init -reconfigure
```

`make bootstrap-state` runs Terraform from the no-backend
[bootstrap](./bootstrap) Terraform root and creates only the
`sandbox-terraform-state` Spaces bucket, because the main remote backend bucket
cannot be used until it exists. After this step, initialize the main Terraform
root with `terraform init -reconfigure`.

After the backend is initialized, run the import script so existing resources
are written to remote state:

```bash
terraform init -upgrade
./ci/clickops-import.sh
```

`ci/clickops-import.sh` skips resources already present in state, so it is safe
for the state bucket to have been created by `make bootstrap-state` before the
import.

The script defaults to `SANDBOX_RESERVED_IP=159.203.49.92`; override it if
DigitalOcean has a different address. After importing, inspect the sandbox state
and plan before applying:

```bash
terraform workspace select sandbox
terraform state list
make tf-prod ACTION=plan
```

[DigitalOcean]: https://www.digitalocean.com/
[Fedora CoreOS]: https://fedoraproject.org/coreos/
[isle-site-template]: https://github.com/Islandora-Devops/isle-site-template

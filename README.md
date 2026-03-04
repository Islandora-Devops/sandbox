# Islandora Sandbox <!-- omit in toc -->

[![LICENSE](https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square)](./LICENSE)
[![Deploy](https://github.com/Islandora-Devops/sandbox/actions/workflows/deploy.yml/badge.svg)](https://github.com/Islandora-Devops/sandbox/actions/workflows/deploy.yml)

## Table of Contents <!-- omit in toc -->
- [Introduction](#introduction)
- [Requirements](#requirements)
- [GitHub Actions](#github-actions)
  - [Deployment Flow](#deployment-flow)
  - [Workflows](#workflows)
  - [Deployment Environments](#deployment-environments)
  - [Environment Variables](#environment-variables)
  - [Secrets](#secrets)
  - [Domains](#domains)

## Introduction

This repository deploys the [Islandora Sandbox] on [Digital Ocean] using
[Fedora CoreOS] and [isle-site-template]. It serves as a reference example of
how to deploy Islandora on DigitalOcean using GitHub Actions.

It is **not** intended as a starting point for new users or those unfamiliar
with Docker and basic server administration.

If you are looking to use Islandora, please read the [official documentation]
and use [isle-site-template] to deploy via Docker, or the
[islandora-playbook] to deploy via Ansible.

## Requirements

- A [Digital Ocean] account with a reserved IP address per environment
- A Fedora CoreOS snapshot created via [snapshot.yml] (see below)
- GitHub repository secrets and variables configured (see [Secrets] and [Environment Variables])

## GitHub Actions

### Deployment Flow

| Event | Test (test.islandora.ca) | Sandbox (sandbox.islandora.ca) |
| :---- | :----------------------- | :----------------------------- |
| PR opened / commit pushed to PR | Deployed, health checked, then **destroyed** | — |
| Merged to `main` | — | Deployed |

On each PR event a fresh droplet is created, [isle-site-template] is cloned and
initialised, a health check polls `/node/1?_format=json` for up to 15 minutes,
and the droplet is **always destroyed afterward** — whether the check passed or
failed — to avoid unnecessary billing.

### Workflows

| Workflow | Trigger | Description |
| :------- | :------ | :---------- |
| [deploy.yml] | PR opened/updated, push to `main` | Deploys to test on PRs (destroyed after health check); deploys to sandbox on merge to `main`. |
| [snapshot.yml] | Monthly (1st) or manually | Imports the latest stable Fedora CoreOS DigitalOcean image into your account and prunes old `coreos`-tagged snapshots. |
| [create.yml] | Called by [deploy.yml] | Creates a DigitalOcean droplet, clones [isle-site-template], runs `make init build demo-objects`, health checks the site, and assigns the reserved IP. Destroys any pre-existing droplet with the same name first. |

### Deployment Environments

Two [deployment environments] are defined in the [environment settings] of the
GitHub repository:

- `test` — ephemeral, destroyed after each health check
- `sandbox` — long-lived, deployed on every merge to `main`

### Environment Variables

Each environment has the following variables:

| Variable | test | sandbox |
| :------- | :--- | :------ |
| `DOMAIN` | `test.islandora.ca` | `sandbox.islandora.ca` |
| `RESERVED_IP_ADDRESS` | `174.138.112.33` | `159.203.49.92` |

The following variables are shared across both environments:

| Variable | Example | Description |
| :------- | :------ | :---------- |
| `REGION` | `tor1 nyc1 nyc3` | Space-separated list of DigitalOcean regions in preference order. The first region with an available size is used. |
| `SIZE` | `s-4vcpu-8gb-amd s-4vcpu-8gb-intel s-4vcpu-8gb` | Space-separated list of droplet sizes in preference order. Tried in order within each region until one is available. |
| `SSH_KEY_NAME` | `default` | Name of the SSH key in your DigitalOcean account deployed to the droplet. |

The snapshot image is selected automatically by querying for the most recently
created DigitalOcean image tagged `coreos`. Run [snapshot.yml] to create or
refresh it.

### Secrets

| Secret | Description |
| :----- | :---------- |
| `DIGITALOCEAN_API_TOKEN` | DigitalOcean API token with read/write access. |
| `ISLE_PASSWORD` | Password written to the `ACTIVEMQ_WEB_ADMIN_PASSWORD` and `DRUPAL_DEFAULT_ACCOUNT_PASSWORD` secret files consumed by [isle-site-template]. |

### Domains

Domains are registered via [hover] but use [Digital Ocean] nameservers, as
LetsEncrypt DNS challenges are not supported by [hover]. The `DOMAIN` and
`RESERVED_IP_ADDRESS` for each environment must match the `A Records` configured
in [Digital Ocean].

TLS certificates are issued via Let's Encrypt HTTP challenge and managed by
Traefik within the [isle-site-template] stack. Certificates are not persisted
across deployments.

[create.yml]: .github/workflows/create.yml
[deploy.yml]: .github/workflows/deploy.yml
[deployment environments]: https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment
[Digital Ocean]: https://www.digitalocean.com/
[environment settings]: https://github.com/Islandora-Devops/sandbox/settings/environments
[Fedora CoreOS]: https://fedoraproject.org/coreos/
[Github Actions]: https://docs.github.com/en/actions/quickstart
[hover]: https://www.hover.com/
[Islandora Sandbox]: https://sandbox.islandora.ca/
[islandora-playbook]: https://github.com/Islandora-Devops/islandora-playbook
[isle-site-template]: https://github.com/Islandora-Devops/isle-site-template
[official documentation]: https://islandora.github.io/documentation/
[reusable workflows]: https://docs.github.com/en/actions/using-workflows/reusing-workflows
[Secrets]: #secrets
[snapshot.yml]: .github/workflows/snapshot.yml

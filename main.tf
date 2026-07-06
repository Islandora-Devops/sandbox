terraform {
  required_version = "~> 1.11"

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

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {}

# This imports the remote-state Space into the sandbox workspace for drift
# visibility. Do not enable sandbox destroy without first moving this bucket out
# of the state it stores.
resource "digitalocean_spaces_bucket" "terraform_state" {
  count  = terraform.workspace == "sandbox" ? 1 : 0
  name   = "sandbox-terraform-state"
  region = "tor1"
  acl    = "private"
}

locals {
  supported_workspaces = {
    sandbox = {
      domain             = var.sandbox_domain
      manages_shared_dns = true
      production         = true
    }
    test = {
      domain             = var.test_domain
      manages_shared_dns = false
      production         = false
    }
  }

  environment       = try(local.supported_workspaces[terraform.workspace], null)
  manage_shared_dns = local.environment != null && local.environment.manages_shared_dns

  base_env = {
    for match in regexall("(?m)^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", file("${path.module}/.env")) :
    match[0] => match[1]
  }
  workspace_env_overrides = local.environment == null ? {} : {
    COMPOSE_PROJECT_NAME = terraform.workspace
    DOMAIN               = local.environment.domain
    TAG                  = terraform.workspace
  }
  runtime_env = merge(local.base_env, local.workspace_env_overrides, {
    ISLE_PASSWORD = var.isle_password
  })

  acme_email          = trimspace(var.acme_email) != "" ? trimspace(var.acme_email) : trimspace(try(local.base_env.ACME_EMAIL, ""))
  sitectl_context     = terraform.workspace
  sitectl_environment = local.environment != null && local.environment.production ? "production" : "non-production"
}

moved {
  from = module.environment["sandbox"].digitalocean_droplet.this
  to   = module.cloud_compose["sandbox"].module.digitalocean.digitalocean_droplet.cloud_compose
}

moved {
  from = module.environment["test"].digitalocean_droplet.this
  to   = module.cloud_compose["test"].module.digitalocean.digitalocean_droplet.cloud_compose
}

resource "terraform_data" "workspace_guard" {
  input = terraform.workspace

  lifecycle {
    precondition {
      condition     = local.environment != null
      error_message = "Unsupported Terraform workspace \"${terraform.workspace}\". Supported workspaces: sandbox, test."
    }
  }
}

module "cloud_compose" {
  for_each = local.environment == null ? {} : { (terraform.workspace) = local.environment }
  source   = "https://github.com/libops/cloud-compose/archive/refs/tags/0.10.0.zip//cloud-compose-0.10.0/providers/do"

  name     = terraform.workspace
  template = "isle"

  digitalocean = {
    region = var.region
    tags   = ["cloud-compose", "islandora-sandbox", terraform.workspace]

    droplet = {
      size     = var.droplet_size
      image    = var.droplet_image
      ssh_keys = var.droplet_ssh_keys
    }

    ssh = {
      cloud_compose_keys = var.ssh_keys
    }

    volumes = {
      data_size_gb           = var.data_volume_size_gb
      docker_volumes_size_gb = var.docker_volumes_volume_size_gb
    }
  }

  runtime = {
    rootfs = "${path.module}/rootfs"

    compose = {
      repo   = var.repo_url
      branch = var.repo_branch
      ingress = {
        letsencrypt    = true
        bot_mitigation = true
        domain         = each.value.domain
        acme_email     = local.acme_email
      }
      init = [
        "grep -v '^ISLE_PASSWORD=' /home/cloud-compose/.env > .env",
        "sitectl config set-context \"$${SITECTL_CONTEXT_NAME}\" --type local --project-dir \"$${DOCKER_COMPOSE_DIR}\" --site \"$${CLOUD_COMPOSE_INSTANCE_NAME}\" --plugin \"$${SITECTL_PLUGIN}\" --environment \"$${SITECTL_ENVIRONMENT}\" --project-name \"$${CLOUD_COMPOSE_INSTANCE_NAME}\" --compose-project-name \"$${COMPOSE_PROJECT_NAME}\" --docker-socket /var/run/docker.sock --env-file .env --default",
        "if [ -n \"$${ISLE_PASSWORD:-}\" ]; then mkdir -p ./secrets; printf '%s' \"$${ISLE_PASSWORD}\" > ./secrets/ACTIVEMQ_WEB_ADMIN_PASSWORD; printf '%s' \"$${ISLE_PASSWORD}\" > ./secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD; chmod 0600 ./secrets/ACTIVEMQ_WEB_ADMIN_PASSWORD ./secrets/DRUPAL_DEFAULT_ACCOUNT_PASSWORD; fi",
        "sudo systemctl daemon-reload",
        "sudo systemctl enable --now rake.timer",
      ]
      up = [
        "if make -n demo-objects >/dev/null 2>&1; then GITHUB_ACTIONS=true TERM=xterm make init build demo-objects; else sitectl compose --context \"$${SITECTL_CONTEXT_NAME}\" up -d --remove-orphans; fi",
        "sitectl healthcheck --context \"$${SITECTL_CONTEXT_NAME}\" --persist --timeout \"$${SITECTL_HEALTHCHECK_TIMEOUT}\" --interval \"$${SITECTL_HEALTHCHECK_INTERVAL}\"",
        "if [ \"$${SITECTL_ENVIRONMENT}\" != \"production\" ]; then sitectl verify --context \"$${SITECTL_CONTEXT_NAME}\" $${SITECTL_VERIFY_ARGS:-}; fi",
      ]
    }

    sitectl = {
      context_name         = local.sitectl_context
      environment          = local.sitectl_environment
      healthcheck_timeout  = "20m"
      healthcheck_interval = "15s"
    }

    managed_runtime = {
      internal_services_enabled     = false
      internal_services_auto_update = false
    }

    extra_env = local.runtime_env
  }

  depends_on = [terraform_data.workspace_guard]
}

module "environment" {
  for_each = local.environment == null ? {} : { (terraform.workspace) = local.environment }
  source   = "./modules/environment"

  domain     = each.value.domain
  droplet_id = module.cloud_compose[each.key].instance_id
  region     = var.region
}

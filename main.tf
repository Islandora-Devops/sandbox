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
    }
    test = {
      domain             = var.test_domain
      manages_shared_dns = false
    }
  }

  environment       = try(local.supported_workspaces[terraform.workspace], null)
  manage_shared_dns = local.environment != null && local.environment.manages_shared_dns

  # renovate: datasource=custom.fedora-coreos packageName=stable versioning=loose
  coreos_version = "44.20260510.3.1"

  rootfs_files = {
    for f in fileset("${path.module}/rootfs", "**") : f => {
      content_b64 = base64encode(file("${path.module}/rootfs/${f}"))
      mode        = endswith(f, ".sh") ? "0755" : "0644"
    }
  }

  base_env_contents = file("${path.module}/.env")
  workspace_env_overrides = local.environment == null ? {} : {
    DOMAIN = local.environment.domain
    TAG    = terraform.workspace
  }
  environment_contents = join("\n", concat(
    [
      for line in split("\n", local.base_env_contents) : line
      if !contains(keys(local.workspace_env_overrides), try(regex("^([A-Za-z_][A-Za-z0-9_]*)=", line)[0], ""))
    ],
    [
      for key, value in local.workspace_env_overrides : "${key}=${value}"
    ],
    [""]
  ))

  cloud_init = local.environment == null ? "" : templatefile("${path.module}/templates/cloud-init.yml", {
    SSH_KEYS          = var.ssh_keys
    ISLE_PASSWORD_B64 = base64encode(var.isle_password)
    SANDBOX_ENV_B64   = base64encode(local.environment_contents)
    REPO_URL_B64      = base64encode(var.repo_url)
    REPO_BRANCH_B64   = base64encode(var.repo_branch)
    ROOTFS_FILES      = local.rootfs_files
  })
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

resource "digitalocean_custom_image" "coreos" {
  count        = local.environment == null ? 0 : 1
  name         = "fedora-coreos-${local.coreos_version}-${terraform.workspace}-${var.region}"
  url          = "https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${local.coreos_version}/x86_64/fedora-coreos-${local.coreos_version}-digitalocean.x86_64.qcow2.gz"
  regions      = [var.region]
  description  = "Terraform-managed Fedora CoreOS image for the ${terraform.workspace} workspace"
  distribution = "Fedora"
  tags         = ["coreos", terraform.workspace]

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [terraform_data.workspace_guard]
}

module "environment" {
  for_each = local.environment == null ? {} : { (terraform.workspace) = local.environment }
  source   = "./modules/environment"

  domain           = each.value.domain
  droplet_name     = terraform.workspace
  droplet_ssh_keys = var.droplet_ssh_keys
  image_id         = digitalocean_custom_image.coreos[0].id
  region           = var.region
  size             = var.droplet_size
  user_data        = local.cloud_init
}

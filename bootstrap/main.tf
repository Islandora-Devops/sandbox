terraform {
  required_version = "~> 1.11"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {}

resource "digitalocean_spaces_bucket" "terraform_state" {
  name   = "sandbox-terraform-state"
  region = "tor1"
  acl    = "private"
}

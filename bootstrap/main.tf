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

# Bootstrap creates the Space that later stores the main Terraform state. The
# main root imports the same bucket for drift visibility, so sandbox destroy
# must remain disabled unless the backend is moved first.
resource "digitalocean_spaces_bucket" "terraform_state" {
  name   = "sandbox-terraform-state"
  region = "tor1"
  acl    = "private"
}

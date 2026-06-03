terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

resource "digitalocean_reserved_ip" "this" {
  region = var.region

  lifecycle {
    ignore_changes = [droplet_id]
  }
}

resource "digitalocean_domain" "this" {
  name = var.domain
}

resource "digitalocean_record" "root_a" {
  domain = digitalocean_domain.this.id
  type   = "A"
  name   = "@"
  value  = digitalocean_reserved_ip.this.ip_address
  ttl    = 900
}

resource "digitalocean_record" "wildcard_cname" {
  domain = digitalocean_domain.this.id
  type   = "CNAME"
  name   = "*"
  value  = "${var.domain}."
  ttl    = 900
}

resource "digitalocean_droplet" "this" {
  name      = var.droplet_name
  region    = var.region
  size      = var.size
  image     = var.image_id
  user_data = var.user_data

  lifecycle {
    create_before_destroy = true
  }
}

resource "digitalocean_reserved_ip_assignment" "this" {
  ip_address = digitalocean_reserved_ip.this.ip_address
  droplet_id = digitalocean_droplet.this.id
}

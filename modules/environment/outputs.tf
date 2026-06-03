output "reserved_ip" {
  description = "Reserved IP attached to the environment droplet"
  value       = digitalocean_reserved_ip.this.ip_address
}

output "region" {
  description = "DigitalOcean region selected for the environment droplet"
  value       = digitalocean_droplet.this.region
}

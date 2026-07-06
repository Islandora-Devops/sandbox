variable "domain" {
  type        = string
  description = "Fully qualified domain name for the environment"
}

variable "droplet_id" {
  type        = string
  description = "DigitalOcean droplet ID that should receive the environment reserved IP"
}

variable "region" {
  type        = string
  description = "DigitalOcean region for the environment resources"
}

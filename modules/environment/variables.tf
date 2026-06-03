variable "domain" {
  type        = string
  description = "Fully qualified domain name for the environment"
}

variable "droplet_name" {
  type        = string
  description = "Name to assign to the environment droplet"
}

variable "image_id" {
  type        = string
  description = "DigitalOcean image ID to use for the droplet"
}

variable "droplet_ssh_keys" {
  type        = list(string)
  description = "DigitalOcean SSH key IDs or fingerprints to attach when creating the droplet"
}

variable "region" {
  type        = string
  description = "DigitalOcean region for the environment resources"
}

variable "size" {
  type        = string
  description = "DigitalOcean droplet size slug"
}

variable "user_data" {
  type        = string
  description = "Rendered Ignition payload for the droplet"
  sensitive   = true
}

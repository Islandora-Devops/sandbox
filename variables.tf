variable "ssh_keys" {
  type        = list(string)
  description = "SSH public keys to authorize for the core user on all droplets"

  default = []
}

variable "github_ssh_keys" {
  type        = list(string)
  default     = []
  description = "Public SSH keys retrieved from authorized GitHub accounts"
}

variable "droplet_ssh_keys" {
  type        = list(string)
  description = "DigitalOcean SSH key IDs or fingerprints to attach when creating droplets"

  # DigitalOcean account-local key ID; update when the account's deploy key changes.
  default = ["34230062"]
}

variable "isle_password" {
  type        = string
  sensitive   = true
  description = "Password for ACTIVEMQ_WEB_ADMIN_PASSWORD and DRUPAL_DEFAULT_ACCOUNT_PASSWORD"
}

variable "packer_ssh_public_key" {
  type        = string
  description = "Public key derived from the deployment SSH private key"
}

variable "sandbox_domain" {
  type        = string
  default     = "sandbox.islandora.ca"
  description = "Domain name for the sandbox workspace"
}

variable "sandbox_slots" {
  type = list(string)
}

variable "sandbox_active_slot" {
  type = string
}

variable "region" {
  type        = string
  default     = "tor1"
  description = "DigitalOcean region selected for the environment droplet and CoreOS custom image"
}

variable "droplet_size" {
  type        = string
  default     = "s-4vcpu-8gb-amd"
  description = "DigitalOcean droplet size slug"
}

variable "deployment_requested_size" {
  type        = string
  default     = null
  description = "Preferred size used for deployment fingerprinting when a capacity fallback is needed"
}

variable "repo_url" {
  type        = string
  default     = "https://github.com/Islandora-Devops/isle-site-template"
  description = "Git repository URL to clone as the isle-site-template"
}

variable "repo_branch" {
  type        = string
  default     = "main"
  description = "Git branch to clone from the isle-site-template repository"
}

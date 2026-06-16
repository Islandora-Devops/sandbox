variable "ssh_keys" {
  type        = list(string)
  description = "SSH public keys to authorize for the core user on all droplets"

  # Operator-maintained public keys. These are intentionally committed for
  # bootstrap access, but should be reviewed when maintainers change.
  default = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC92mfUd/zMuzWqAod/xuqrE2to4ae1cRiknK81uMHfVHpXoxx2xM7PkmMsO9ShQtWsu0V0q4A9kozzv22HVDL51iVapESrM4q2KWiDHnE45U8RH/DDRX5NdW3+GvNQk2ITyHR4CVpvwYXCYfI4bha4R4jF7oc7pDmLcgcYN+9OSptUnWUbxqiWqfuwWSmux9N1HHiVDTt/2W8qgszAzwXI64ooK5pkU7KSXQ9A/w4Ra/xmZioCKAB4MZh5HIwNoVgZ8OCXLBL66cQTJEQnmkCc3rVeHikBhvUxCnKWGmdjcBG/XGxqHIQ1HVn7GSlclJ8hGISZZcBaB4RVFCUK4i8tvKbM1dHNyNnZGAWJUCMQDH8Dkx8wnOAWdq4ed1cd16Jt3y4cEcHEUSXmZmViYMNHbqqL+yaj3nhCDIwa7CzoVLZ4Vj8xOvn/X2JMaLPhJFY//5Y6Dep01Nm+4d0Xf4gYo3H6Hmo/jBeXO/VRPHKbbZIMlA04mrlClosgUqkm+cE=",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHZds7DX1z9IN0T7H/yXZrUIlOHiPzqK9oWN8brKh06e jjc223@Mac",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDpnsCo+43hAzcECq+2gro/s8OrsRNVZFsnVWb7Dt+Tv aOelschlager"
  ]
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

variable "test_domain" {
  type        = string
  default     = "test.islandora.ca"
  description = "Domain name for the test workspace"
}

variable "sandbox_domain" {
  type        = string
  default     = "sandbox.islandora.ca"
  description = "Domain name for the sandbox workspace"
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

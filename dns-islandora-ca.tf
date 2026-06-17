locals {
  islandora_ca_a_records = {
    "@"        = { value = "198.202.211.1", ttl = 300 }
    "dev"      = { value = "127.0.0.1", ttl = 3600 }
    "automate" = { value = "146.190.188.16", ttl = 900 }
    "webmail"  = { value = "142.251.41.83", ttl = 900 }
    "legacy"   = { value = "137.149.200.49", ttl = 900 }
    "ftp"      = { value = "35.208.233.30", ttl = 900 }
  }

  islandora_ca_cname_records = {
    "www"        = { value = "cdn.webflow.com.", ttl = 300 }
    "2025"       = { value = "islandora-community.github.io.", ttl = 43200 }
    "*.automate" = { value = "automate.islandora.ca.", ttl = 900 }
    "mail"       = { value = "ghs.googlehosted.com.", ttl = 900 }
    "*.sandbox"  = { value = "sandbox.islandora.ca.", ttl = 900 }
  }

  islandora_ca_mx_records = {
    "aspmx.l.google.com."      = 1
    "alt1.aspmx.l.google.com." = 5
    "alt2.aspmx.l.google.com." = 5
    "alt3.aspmx.l.google.com." = 10
    "alt4.aspmx.l.google.com." = 10
  }

  islandora_ca_ns_targets = toset([
    "ns1.digitalocean.com.",
    "ns2.digitalocean.com.",
    "ns3.digitalocean.com.",
  ])
}

resource "digitalocean_domain" "islandora_ca" {
  count = local.manage_shared_dns ? 1 : 0
  name  = "islandora.ca"
}

resource "digitalocean_record" "islandora_ca_a" {
  for_each = local.manage_shared_dns ? local.islandora_ca_a_records : {}

  domain = digitalocean_domain.islandora_ca[0].id
  type   = "A"
  name   = each.key
  value  = each.value.value
  ttl    = each.value.ttl
}

resource "digitalocean_record" "islandora_ca_sandbox_a" {
  for_each = local.manage_shared_dns ? {
    fcrepo  = module.environment[terraform.workspace].reserved_ip
    sandbox = module.environment[terraform.workspace].reserved_ip
  } : {}

  domain = digitalocean_domain.islandora_ca[0].id
  type   = "A"
  name   = each.key
  value  = each.value
  ttl    = 900
}

resource "digitalocean_record" "islandora_ca_cname" {
  for_each = local.manage_shared_dns ? local.islandora_ca_cname_records : {}

  domain = digitalocean_domain.islandora_ca[0].id
  type   = "CNAME"
  name   = each.key
  value  = each.value.value
  ttl    = each.value.ttl
}

resource "digitalocean_record" "islandora_ca_ns_sandbox" {
  for_each = local.manage_shared_dns ? local.islandora_ca_ns_targets : toset([])

  domain = digitalocean_domain.islandora_ca[0].id
  type   = "NS"
  name   = "sandbox"
  value  = each.value
  ttl    = 900
}

resource "digitalocean_record" "islandora_ca_ns_test" {
  for_each = local.manage_shared_dns ? local.islandora_ca_ns_targets : toset([])

  domain = digitalocean_domain.islandora_ca[0].id
  type   = "NS"
  name   = "test"
  value  = each.value
  ttl    = 900
}

resource "digitalocean_record" "islandora_ca_mx" {
  for_each = local.manage_shared_dns ? local.islandora_ca_mx_records : {}

  domain   = digitalocean_domain.islandora_ca[0].id
  type     = "MX"
  name     = "@"
  priority = each.value
  value    = each.key
  ttl      = 1800
}

resource "digitalocean_record" "islandora_ca_txt_github_pages_challenge" {
  count  = local.manage_shared_dns ? 1 : 0
  domain = digitalocean_domain.islandora_ca[0].id
  type   = "TXT"
  name   = "_github-pages-challenge-islandora-community"
  value  = "905ebdfa59b9ba832c27c318815d8a"
  ttl    = 3600
}

resource "digitalocean_record" "islandora_ca_txt_dkim_google" {
  count  = local.manage_shared_dns ? 1 : 0
  domain = digitalocean_domain.islandora_ca[0].id
  type   = "TXT"
  name   = "google._domainkey"
  value  = "v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCOTce+cNispDTOmtsIaciukOB3jyDncu9VScA643DfSqvXUUXQXK813kr0ANkE5Kg6mkb3DmEWraiVEkF77Fcd0G3ZeCF4PpqnJFiMpd4CYjZQPUeXiP4x4iiBnvQbQV8oZaaiq3jXeyUwY27A6/mYfKDQS32MY3zVFtOw+9neJwIDAQAB"
  ttl    = 900
}

resource "digitalocean_record" "islandora_ca_txt_domainkey" {
  count  = local.manage_shared_dns ? 1 : 0
  domain = digitalocean_domain.islandora_ca[0].id
  type   = "TXT"
  name   = "_domainkey"
  value  = "v=DKIM1; o=~"
  ttl    = 900
}

resource "digitalocean_record" "islandora_ca_txt_google_verify" {
  count  = local.manage_shared_dns ? 1 : 0
  domain = digitalocean_domain.islandora_ca[0].id
  type   = "TXT"
  name   = "@"
  value  = "google-site-verification=WC57eo9SoIqzU8qHIOhZuEcS-Wj5WTvDju-accRLNCY"
  ttl    = 900
}

resource "digitalocean_record" "islandora_ca_txt_spf" {
  count  = local.manage_shared_dns ? 1 : 0
  domain = digitalocean_domain.islandora_ca[0].id
  type   = "TXT"
  name   = "@"
  value  = "v=spf1 +a +mx +a:us170.siteground.us include:_spf.mailspamprotection.com ~all"
  ttl    = 900
}

# Resolve credentials from SOPS (secrets.enc.yaml) or secrets.auto.tfvars.
# SOPS: set SOPS_AGE_KEY_FILE to your age private key file before plan/apply.

data "sops_file" "secrets" {
  count       = fileexists("${path.module}/secrets.enc.yaml") ? 1 : 0
  source_file = "${path.module}/secrets.enc.yaml"
}

locals {
  secrets_from_sops = length(data.sops_file.secrets) > 0 ? data.sops_file.secrets[0].data : {}

  proxmox_api_token = coalesce(
    try(local.secrets_from_sops["proxmox_api_token"], null),
    var.proxmox_api_token,
  )
  git_token = coalesce(
    try(local.secrets_from_sops["git_token"], null),
    var.git_token,
  )
  sops_age_private_key = coalesce(
    try(local.secrets_from_sops["sops_age_private_key"], null),
    var.sops_age_private_key,
  )
}

check "secrets_configured" {
  assert {
    condition = (
      local.proxmox_api_token != null &&
      local.git_token != null &&
      local.sops_age_private_key != null
    )
    error_message = "Provide proxmox_api_token, git_token, and sops_age_private_key via secrets.auto.tfvars or secrets.enc.yaml (with SOPS_AGE_KEY_FILE set)."
  }
}

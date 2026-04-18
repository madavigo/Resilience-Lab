terraform {
  required_version = ">= 1.6"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.0"
    }
  }

  # Copy this block and set a unique `key` per environment.
  # e.g. for a "prod" environment: key = "prod/terraform.tfstate"
  backend "s3" {
    endpoint = "https://minio.madavigo.com"
    bucket   = "terraform-state"
    key      = "<env-name>/terraform.tfstate" # CHANGE THIS
    region   = "us-east-1"

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}

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
    opnsense = {
      source  = "browningluke/opnsense"
      version = "~> 0.10"
    }
    vultr = {
      source  = "vultr/vultr"
      version = "~> 2.27"
    }
  }

  # S3-compatible remote state backed by MinIO on TrueNAS.
  # The backend "s3" block is identical to real AWS S3 except for the three
  # skip_* flags and force_path_style. Swap the endpoint + remove those flags
  # and this works against a real AWS bucket unchanged.
  #
  # Credentials: set via environment variables (never in source):
  #   export AWS_ACCESS_KEY_ID=<minio-access-key>
  #   export AWS_SECRET_ACCESS_KEY=<minio-secret-key>
  backend "s3" {
    endpoint = "https://minio.madavigo.com"
    bucket   = "terraform-state"
    key      = "lab/terraform.tfstate"
    region   = "us-east-1" # required by the S3 backend; irrelevant for MinIO

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}

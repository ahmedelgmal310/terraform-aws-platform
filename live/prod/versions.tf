terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.68.0"
    }
  }

  # Partial configuration: the bucket, lock table and key come from
  # backend.hcl (see backend.hcl.example). CI replaces this with a local
  # backend through an override file, so no real state bucket is needed there.
  backend "s3" {}
}

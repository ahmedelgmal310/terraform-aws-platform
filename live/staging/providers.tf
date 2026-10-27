provider "aws" {
  region = var.region

  # Guard rail against applying an environment to the wrong account.
  allowed_account_ids = length(var.allowed_account_ids) > 0 ? var.allowed_account_ids : null

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      Owner       = var.owner
      ManagedBy   = "terraform"
      Repository  = var.github_repository
    }
  }
}

#!/usr/bin/env bash
# Writes a git-ignored *_override.tf into a root module so CI can plan it
# against LocalStack: local state instead of the S3 backend, and provider
# settings that skip real-AWS credential checks. The endpoint itself comes from
# AWS_ENDPOINT_URL. Nothing here is used outside CI.
# Usage: scripts/localstack-override.sh <root-module-dir>
set -euo pipefail

dir="$1"
backend=""
if grep -q 'backend "s3"' "$dir"/*.tf; then
  backend='terraform {
  backend "local" {}
}
'
fi

cat > "$dir/localstack_override.tf" <<EOF
${backend}
provider "aws" {
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true
}
EOF
echo "wrote $dir/localstack_override.tf"

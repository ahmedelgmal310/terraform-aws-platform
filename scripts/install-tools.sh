#!/usr/bin/env bash
# Installs pinned CLI tools into ./.bin after verifying their SHA-256.
# Usage: scripts/install-tools.sh tflint terraform-docs opa conftest
# Versions and checksums are the single source of truth for CI and local use;
# Dependabot cannot bump these, so update them together with the checksum.
set -euo pipefail

BIN_DIR="${BIN_DIR:-$PWD/.bin}"
mkdir -p "$BIN_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

TFLINT_VERSION="v0.64.0"
TFLINT_SHA256="cca9d13e2e1d7a2c627af60ff899a3c9b74212899416aeb96ec764d2ef954537"
TFDOCS_VERSION="v0.24.0"
TFDOCS_SHA256="9005daf969de0b50134493a2c00078b49f5f5b39d021cda7c89bf4d4f3d776d3"
OPA_VERSION="v1.21.1"
OPA_SHA256="668506eb17a2eaa1fce6cc0d1f42ef85125d4ac5bda5fc74d1152d0c77145031"
CONFTEST_VERSION="0.71.1"
CONFTEST_SHA256="c3f6b2a753bd56e377a1e51a95ae3e057f926f2e9139f7d5b5dfbbaf810f7985"

fetch() { # url sha256 dest
  curl -fsSL --retry 3 -o "$3" "$1"
  echo "$2  $3" | sha256sum --check --quiet
}

for tool in "$@"; do
  case "$tool" in
    tflint)
      fetch "https://github.com/terraform-linters/tflint/releases/download/${TFLINT_VERSION}/tflint_linux_amd64.zip" "$TFLINT_SHA256" "$TMP/tflint.zip"
      unzip -q -o "$TMP/tflint.zip" -d "$BIN_DIR"
      ;;
    terraform-docs)
      fetch "https://github.com/terraform-docs/terraform-docs/releases/download/${TFDOCS_VERSION}/terraform-docs-${TFDOCS_VERSION}-linux-amd64.tar.gz" "$TFDOCS_SHA256" "$TMP/tfdocs.tgz"
      tar -xzf "$TMP/tfdocs.tgz" -C "$BIN_DIR" terraform-docs
      ;;
    opa)
      fetch "https://github.com/open-policy-agent/opa/releases/download/${OPA_VERSION}/opa_linux_amd64_static" "$OPA_SHA256" "$BIN_DIR/opa"
      ;;
    conftest)
      fetch "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz" "$CONFTEST_SHA256" "$TMP/conftest.tgz"
      tar -xzf "$TMP/conftest.tgz" -C "$BIN_DIR" conftest
      ;;
    *)
      echo "unknown tool: $tool" >&2
      exit 1
      ;;
  esac
  chmod +x "$BIN_DIR"/* 2>/dev/null || true
  echo "installed $tool"
done

if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$BIN_DIR" >> "$GITHUB_PATH"
fi

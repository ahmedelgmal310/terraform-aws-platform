#!/usr/bin/env bash
# Renders a Markdown summary of `terraform show -json` output.
# Usage: scripts/plan-summary.sh <plan.json> <title>
set -euo pipefail

plan="$1"
title="$2"

jq -r --arg title "$title" '
  [.resource_changes[] | select(.mode == "managed")] as $rc
  | ($rc | map(select(.change.actions != ["no-op"]))) as $changed
  | "### \($title)",
    "",
    "Terraform \(.terraform_version), \($changed | length) managed resources in the plan.",
    "",
    "| Action | Count |",
    "|---|---:|",
    ($changed | group_by(.change.actions | join("/")) | .[] | "| \(.[0].change.actions | join("/")) | \(length) |"),
    "",
    "<details><summary>Resources by type</summary>",
    "",
    "| Type | Count |",
    "|---|---:|",
    ($changed | group_by(.type) | sort_by(-length, .[0].type) | .[] | "| `\(.[0].type)` | \(length) |"),
    "",
    "</details>",
    ""
' "$plan"

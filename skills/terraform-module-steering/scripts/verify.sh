#!/usr/bin/env bash
# verify.sh — run the verification pipeline on a Terraform module (the definition of "done").
# Usage: bash verify.sh [module-dir]   (defaults to the current directory)
#
# Stages: terraform fmt -> init -> validate -> tflint -> terraform test -> checkov.
# checkov scans examples/minimal/ when present (the example instantiates the module with real
# inputs); otherwise the module root. Exits non-zero if any stage fails. Missing optional tools
# (tflint, checkov) are skipped with a note. See references/verification-pipeline.md for the why.
set -uo pipefail

DIR="${1:-.}"
cd "$DIR" || { echo "no such dir: $DIR"; exit 2; }
echo "## verifying: $(pwd)"
fail=0

echo "== terraform fmt =="
terraform fmt -check -recursive || { echo "  FAIL: run 'terraform fmt -recursive'"; fail=1; }

echo "== terraform init =="
terraform init -backend=false -no-color >/dev/null || { echo "  FAIL: init"; fail=1; }

echo "== terraform validate =="
terraform validate -no-color || fail=1

echo "== tflint =="
if command -v tflint >/dev/null 2>&1; then
  [ -f .tflint.hcl ] && tflint --init >/dev/null 2>&1
  tflint --recursive || fail=1
else
  echo "  (tflint not installed — skipped)"
fi

echo "== terraform test =="
terraform test -no-color || fail=1

echo "== checkov =="
if command -v checkov >/dev/null 2>&1; then
  if [ -d examples/minimal ]; then target="examples/minimal"; else target="."; fi
  cfg=(); [ -f .checkov.yaml ] && cfg=(--config-file .checkov.yaml)
  checkov -d "$target" "${cfg[@]}" --download-external-modules true --compact --quiet || fail=1
else
  echo "  (checkov not installed — skipped)"
fi

echo
if [ "$fail" -eq 0 ]; then echo "PIPELINE: GREEN"; else echo "PIPELINE: RED"; fi
exit "$fail"

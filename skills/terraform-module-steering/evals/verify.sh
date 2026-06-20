#!/usr/bin/env bash
# verify.sh — run the terraform-module-steering verification pipeline on a module dir.
# Usage: ./verify.sh <module-dir>   (defaults to the current directory)
#
# Runs: terraform fmt -> init -> validate -> tflint -> terraform test -> checkov.
# Exits non-zero if any stage fails. Tools that are not installed are skipped with a note.
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
  tflint || fail=1
else
  echo "  (tflint not installed — skipped)"
fi

echo "== terraform test =="
terraform test -no-color || fail=1

echo "== checkov =="
if command -v checkov >/dev/null 2>&1; then
  checkov -d . --compact --quiet --framework terraform || fail=1
else
  echo "  (checkov not installed — skipped)"
fi

echo
if [ "$fail" -eq 0 ]; then echo "PIPELINE: GREEN"; else echo "PIPELINE: RED"; fi
exit "$fail"

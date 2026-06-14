#!/usr/bin/env bash
# setup-workspace.sh — verify (and optionally install) the Terraform module workspace.
#
#   (no args)   REPORT ONLY — list present/missing CLIs and plugins. Changes nothing.
#   --install   Install the missing required items (run only after the creator consents).
#
# Produces/installs local tooling only. Performs NO git operations on the user's repositories.
set -uo pipefail

# Tools installed via pipx / release zips commonly land here but aren't always on PATH.
export PATH="$HOME/.local/bin:$PATH"

INSTALL=0
[[ "${1:-}" == "--install" ]] && INSTALL=1

have() { command -v "$1" >/dev/null 2>&1; }
MISSING_CLI=()
MISSING_PLUGIN=()

# ---------------------------------------------------------------- CLI checks
check_cli() { # bin  label  req|opt
  if have "$1"; then
    printf "  [ok]   %-15s %s\n" "$2" "$("$1" --version 2>/dev/null | head -1)"
  else
    printf "  [MISS] %-15s missing (%s)\n" "$2" "$3"
    [[ "$3" == required ]] && MISSING_CLI+=("$1")
  fi
}

echo "== CLIs =="
check_cli terraform      terraform      required
check_cli tflint         tflint         required
check_cli checkov        checkov        required
check_cli terraform-docs terraform-docs optional
check_cli trivy          trivy          optional

# ------------------------------------------------------------- Plugin checks
INSTALLED_JSON="$HOME/.claude/plugins/installed_plugins.json"
plugin_installed() { [[ -f "$INSTALLED_JSON" ]] && grep -q "\"$1\"" "$INSTALLED_JSON"; }
check_plugin() { # ref  req|opt
  if plugin_installed "$1"; then
    printf "  [ok]   %s\n" "$1"
  else
    printf "  [MISS] %s missing (%s)\n" "$1" "$2"
    [[ "$2" == required ]] && MISSING_PLUGIN+=("$1")
  fi
}

echo "== Plugins =="
check_plugin "terraform-skill@antonbabenko"      required
check_plugin "context7@claude-plugins-official"  required
check_plugin "code-intelligence@antonbabenko"    optional

# ------------------------------------------------------------- report mode
if [[ $INSTALL -eq 0 ]]; then
  echo ""
  if [[ ${#MISSING_CLI[@]} -eq 0 && ${#MISSING_PLUGIN[@]} -eq 0 ]]; then
    echo "All required tools present — workspace ready."
  else
    echo "Missing required items. After you grant permission, re-run with --install:"
    [[ ${#MISSING_CLI[@]}    -gt 0 ]] && echo "  CLIs:    ${MISSING_CLI[*]}"
    [[ ${#MISSING_PLUGIN[@]} -gt 0 ]] && echo "  Plugins: ${MISSING_PLUGIN[*]}"
    echo "Note: newly-installed plugins load only after a Claude Code restart."
  fi
  exit 0
fi

# ------------------------------------------------------------- install mode
echo ""
echo "== Installing missing required items =="
mkdir -p "$HOME/.local/bin"
arch="$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')"
os="$(uname -s | tr '[:upper:]' '[:lower:]')"

install_cli() {
  case "$1" in
    terraform) have brew && brew install terraform || echo "  -> install terraform manually: https://developer.hashicorp.com/terraform/install" ;;
    tflint)    curl -fsSL "https://github.com/terraform-linters/tflint/releases/latest/download/tflint_${os}_${arch}.zip" -o /tmp/tflint.zip \
                 && unzip -o /tmp/tflint.zip -d "$HOME/.local/bin/" >/dev/null && chmod +x "$HOME/.local/bin/tflint" ;;
    checkov)   if have pipx; then pipx install checkov; else pip3 install --user checkov; fi ;;
  esac
}
for c in "${MISSING_CLI[@]}"; do echo "-- $c"; install_cli "$c"; done

install_plugin() {
  if ! have claude; then echo "  -> 'claude' CLI not on PATH; run: claude plugin install $1 --scope user"; return; fi
  # terraform-skill's source is a separate GitHub repo the installer clones over SSH.
  # Route github SSH -> HTTPS for THIS command only (public repo, no auth), without
  # touching the user's real global git config.
  if [[ "$1" == terraform-skill@* ]]; then
    local tmp="/tmp/tf-steering-gitconfig"
    printf '[include]\n\tpath = %s/.gitconfig\n[url "https://github.com/"]\n\tinsteadOf = git@github.com:\n' "$HOME" > "$tmp"
    GIT_CONFIG_GLOBAL="$tmp" claude plugin install "$1" --scope user </dev/null
  else
    claude plugin install "$1" --scope user </dev/null
  fi
}
for p in "${MISSING_PLUGIN[@]}"; do echo "-- $p"; install_plugin "$p"; done

echo ""
echo "Done. If anything went to ~/.local/bin, ensure it is on your PATH."
echo "IMPORTANT: newly-installed plugins load only after you restart Claude Code."

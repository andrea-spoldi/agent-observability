#!/usr/bin/env bash
# install.sh — Preflight check and dependency installer for agent-observability.
#
# Checks: jq, otel-cli, OTEL collector endpoint reachability.
# Downloads otel-cli if missing (from GitHub releases).
#
# Usage:
#   bash install.sh                    # interactive
#   OTEL_EXPORTER_OTLP_ENDPOINT=http://host:4318 bash install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OTEL_CLI_VERSION="${OTEL_CLI_VERSION:-0.4.5}"
OTEL_ENDPOINT="${OTEL_EXPORTER_OTLP_ENDPOINT:-http://localhost:4318}"
INSTALL_DIR="${OTEL_CLI_INSTALL_DIR:-${HOME}/.local/bin}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}!${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " agent-observability — preflight check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

ERRORS=0

# ---------------------------------------------------------------------------
# 1. jq
# ---------------------------------------------------------------------------
echo "Checking dependencies..."

if command -v jq &>/dev/null; then
  ok "jq $(jq --version 2>/dev/null || echo 'found')"
else
  fail "jq not found"
  echo "     Install: sudo apt-get install jq  OR  brew install jq"
  ERRORS=$((ERRORS + 1))
fi

if command -v curl &>/dev/null; then
  ok "curl found"
else
  fail "curl not found (required at runtime — emit_counter posts OTLP metrics directly)"
  echo "     Install: sudo apt-get install curl  OR  brew install curl"
  ERRORS=$((ERRORS + 1))
fi

# ---------------------------------------------------------------------------
# 2. otel-cli
# ---------------------------------------------------------------------------
if command -v otel-cli &>/dev/null; then
  ok "otel-cli found at $(command -v otel-cli)"
elif [[ -x "${INSTALL_DIR}/otel-cli" ]]; then
  ok "otel-cli found at ${INSTALL_DIR}/otel-cli"
  export PATH="${INSTALL_DIR}:${PATH}"
else
  warn "otel-cli not found — attempting install..."

  # Detect platform
  OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
  ARCH="$(uname -m)"
  case "${ARCH}" in
    x86_64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) fail "Unsupported architecture: ${ARCH}"; ERRORS=$((ERRORS + 1)) ;;
  esac

  if (( ERRORS == 0 )); then
    TARBALL="otel-cli_${OTEL_CLI_VERSION}_${OS}_${ARCH}.tar.gz"
    URL="https://github.com/equinix-labs/otel-cli/releases/download/v${OTEL_CLI_VERSION}/${TARBALL}"

    mkdir -p "${INSTALL_DIR}"
    echo "     Downloading ${URL}..."

    if curl -fsSL "${URL}" | tar xz -C "${INSTALL_DIR}" otel-cli 2>/dev/null; then
      chmod +x "${INSTALL_DIR}/otel-cli"
      ok "otel-cli ${OTEL_CLI_VERSION} installed to ${INSTALL_DIR}/otel-cli"
      export PATH="${INSTALL_DIR}:${PATH}"
    else
      fail "Failed to download otel-cli"
      echo "     Manual install: https://github.com/equinix-labs/otel-cli/releases"
      ERRORS=$((ERRORS + 1))
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 3. Collector endpoint reachability
# ---------------------------------------------------------------------------
echo ""
echo "Checking OTEL collector at ${OTEL_ENDPOINT}..."

# Extract host:port from endpoint URL
HOST_PORT="$(echo "${OTEL_ENDPOINT}" | sed -E 's|https?://||; s|/.*||')"
HOST="${HOST_PORT%%:*}"
PORT="${HOST_PORT##*:}"
[[ "${PORT}" == "${HOST}" ]] && PORT=4318

if timeout 3 bash -c "echo >/dev/tcp/${HOST}/${PORT}" 2>/dev/null; then
  ok "Collector reachable at ${HOST}:${PORT}"
else
  warn "Collector not reachable at ${HOST}:${PORT}"
  echo "     Hooks will still record to session log (${OTEL_SESSION_DIR:-/tmp/agent-otel-session}/)"
  echo "     Start a collector or set OTEL_EXPORTER_OTLP_ENDPOINT to fix"
  echo ""
  echo "     Quick start with Docker:"
  echo "       docker run --rm -p 4317:4317 -p 4318:4318 \\"
  echo "         -v \$(pwd)/assets/otel-collector-config.yaml:/etc/otelcol/config.yaml \\"
  echo "         otel/opentelemetry-collector-contrib:latest"
fi

# ---------------------------------------------------------------------------
# 4. Make hook scripts executable
# ---------------------------------------------------------------------------
echo ""
echo "Setting hook permissions..."
chmod +x "${SCRIPT_DIR}/hooks/"*.sh 2>/dev/null && ok "Hook scripts are executable" \
  || warn "Could not chmod hook scripts"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if (( ERRORS > 0 )); then
  echo -e "${RED}Preflight failed with ${ERRORS} error(s).${NC}"
  exit 1
else
  echo -e "${GREEN}Preflight passed.${NC} Ready to instrument."
  echo ""
  echo "Next steps:"
  echo "  1. Merge assets/hooks.json's \"hooks\" key into .claude/settings.json"
  echo "  2. Start your OTEL collector"
  echo "  3. Run Claude Code normally — hooks fire automatically"
  echo ""
  echo "Session data: ${OTEL_SESSION_DIR:-/tmp/agent-otel-session}/"
  echo "Endpoint:     ${OTEL_ENDPOINT}"
fi

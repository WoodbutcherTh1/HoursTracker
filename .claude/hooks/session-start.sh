#!/bin/bash
set -uo pipefail

# Only run this on Claude Code on the web (remote sessions), not local machines.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

MARKETPLACE_URL="https://github.com/affaan-m/ECC"
MARKETPLACE_NAME="ecc"
PLUGIN_ID="ecc@ecc"

if ! command -v claude >/dev/null 2>&1; then
  echo "session-start hook: 'claude' CLI not found, skipping ECC plugin install" >&2
  exit 0
fi

if claude plugin list 2>/dev/null | grep -q "^\s*>\?\s*${PLUGIN_ID}"; then
  echo "session-start hook: ${PLUGIN_ID} already installed, skipping"
  exit 0
fi

if ! claude plugin marketplace list 2>/dev/null | grep -q "${MARKETPLACE_NAME}"; then
  claude plugin marketplace add "${MARKETPLACE_URL}" \
    || echo "session-start hook: failed to add ECC marketplace, continuing without it" >&2
fi

claude plugin install "${PLUGIN_ID}" \
  || echo "session-start hook: failed to install ${PLUGIN_ID}, continuing without it" >&2

exit 0

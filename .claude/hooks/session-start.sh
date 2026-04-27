#!/bin/bash
set -euo pipefail

# Only run in remote (Claude Code on the web) environments
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

echo '{"async": true, "asyncTimeout": 300000}'

# Sync with latest from GitHub
cd "$CLAUDE_PROJECT_DIR"
git fetch origin
git pull origin main --rebase --autostash

# Install web dependencies
cd "$CLAUDE_PROJECT_DIR/web"
npm install

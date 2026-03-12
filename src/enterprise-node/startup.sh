#!/bin/bash
set -euo pipefail

echo "→ Configuring npm registry..."
npm config set registry "${NPM_CONFIG_REGISTRY}" 2>/dev/null || true

echo "→ Installing Node.js development tools..."
npm install -g typescript typescript-language-server 2>/dev/null || true
npm install -g eslint 2>/dev/null || true
npm install -g prettier 2>/dev/null || true
npm install -g ts-node 2>/dev/null || true

if [ -n "${DOTFILES_URI}" ]; then
  echo "→ Cloning dotfiles from $DOTFILES_URI..."
  coder dotfiles -y "$DOTFILES_URI" 2>/dev/null || true
fi

echo "→ Starting code-server..."
code-server-start

echo "→ Startup complete."

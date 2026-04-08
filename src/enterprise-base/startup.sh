#!/bin/bash
set -euo pipefail

if [ -n "${DOTFILES_URI}" ]; then
  echo "→ Cloning dotfiles from $DOTFILES_URI..."
  coder dotfiles -y "$DOTFILES_URI" 2>/dev/null || true
fi

echo "→ Startup complete."

#!/bin/bash
set -euo pipefail

echo "→ Installing Go development tools..."
export GOPATH="$HOME/go"
export PATH="$PATH:$GOPATH/bin:/usr/local/go/bin"

go install golang.org/x/tools/gopls@latest 2>/dev/null || true

if ! command -v golangci-lint &>/dev/null; then
  curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
    | sh -s -- -b "$GOPATH/bin" 2>/dev/null || true
fi

go install github.com/go-delve/delve/cmd/dlv@latest 2>/dev/null || true
go install golang.org/x/tools/cmd/goimports@latest 2>/dev/null || true
go install honnef.co/go/tools/cmd/staticcheck@latest 2>/dev/null || true

if [ -n "${DOTFILES_URI}" ]; then
  echo "→ Cloning dotfiles from $DOTFILES_URI..."
  coder dotfiles -y "$DOTFILES_URI" 2>/dev/null || true
fi

echo "→ Starting code-server..."
code-server-start &

echo "→ Startup complete."

#!/bin/bash
set -euo pipefail

export NVM_DIR="$HOME/.nvm"
export PATH="$HOME/.local/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"

if [ ! -s "$NVM_DIR/nvm.sh" ]; then
  echo "nvm is missing from $NVM_DIR" >&2
  exit 1
fi

# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh"
nvm use default >/dev/null

mkdir -p "$HOME/repos"
cd "$HOME/repos"

echo "Configuring npm registry..."
npm config set registry "${NPM_CONFIG_REGISTRY}"

if [ -n "${DOTFILES_URI:-}" ]; then
  echo "Installing dotfiles from ${DOTFILES_URI}..."
  coder dotfiles -y "${DOTFILES_URI}"
fi

omx_marker="$HOME/.omx/.coder-template-setup-complete"
if [ ! -f "$omx_marker" ]; then
  echo "Configuring oh-my-codex for the coder user..."
  omx setup --scope user
  mkdir -p "$(dirname "$omx_marker")"
  touch "$omx_marker"
fi

skills_marker="$HOME/.codex/.mattpocock-skills-installed"
if [ ! -f "$skills_marker" ]; then
  echo "Installing mattpocock skills for Codex..."
  npx --yes skills@latest add mattpocock/skills --skill '*' --agent codex --global --yes
  mkdir -p "$(dirname "$skills_marker")"
  touch "$skills_marker"
fi

codex_config="$HOME/.codex/config.toml"
if [ ! -f "$codex_config" ] || ! grep -q 'codegraph' "$codex_config"; then
  echo "Connecting CodeGraph to Codex..."
  codegraph install --target=codex --location=global --yes
fi

echo "omx-codex workspace ready in $HOME/repos."

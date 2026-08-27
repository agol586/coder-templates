#!/bin/bash
# Coder agent startup script for buzz-relay.
#
# Runs on every workspace start. Responsibilities:
#   1. Configure npm/dotfiles as usual for this repository's templates.
#   2. Seed or update the Buzz source checkout at ~/repos/buzz without
#      overwriting dirty developer work.
#   3. Launch buzz-relay-start in the background with logs persisted to the
#      home volume, so a stopped/restarted workspace keeps its relay logs.
set -euo pipefail

export RUSTUP_HOME="$HOME/.rustup"
export CARGO_HOME="$HOME/.cargo"
export NVM_DIR="$HOME/.nvm"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
# shellcheck source=/dev/null
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

mkdir -p "$HOME/repos" "$HOME/.local/state/buzz-relay"

if [ -n "${DOTFILES_URI:-}" ]; then
  echo "Installing dotfiles from ${DOTFILES_URI}..."
  coder dotfiles -y "${DOTFILES_URI}"
fi

# ---------------------------------------------------------------------------
# Seed or update the Buzz source checkout. Never overwrites uncommitted or
# unpushed developer work — matching this repository's existing convention
# (see src/claude-code/main.tf's realworld-django-rest-framework-angular
# clone/pull logic).
# ---------------------------------------------------------------------------
BUZZ_REPO_DIR="$HOME/repos/buzz"
BUZZ_REPO_URL="https://github.com/block/buzz.git"
BUZZ_REF="${BUZZ_REF:-b622003f74aa5bf9b659786452813299a25e4897}"

if [ ! -d "$BUZZ_REPO_DIR/.git" ]; then
  echo "Cloning Buzz source at ${BUZZ_REF}..."
  git clone "$BUZZ_REPO_URL" "$BUZZ_REPO_DIR"
  (cd "$BUZZ_REPO_DIR" && git checkout --detach "$BUZZ_REF")
else
  (
    cd "$BUZZ_REPO_DIR"
    git fetch --quiet origin || echo "Warning: could not fetch updates for $BUZZ_REPO_DIR" >&2
    if git diff-index --quiet HEAD -- && \
        [ -z "$(git status --porcelain --untracked-files=no)" ] && \
        [ -z "$(git log --branches --not --remotes 2>/dev/null)" ]; then
      if [ "$(git rev-parse HEAD)" != "$(git rev-parse "$BUZZ_REF" 2>/dev/null || echo "$BUZZ_REF")" ]; then
        echo "Checking out pinned ref ${BUZZ_REF}..."
        git checkout --detach "$BUZZ_REF"
      fi
    else
      echo "Buzz checkout at $BUZZ_REPO_DIR has local changes; leaving it as-is."
    fi
  )
fi

# ---------------------------------------------------------------------------
# Start the relay under buzz-relay-start, in the background, with logs
# persisted under the home volume.
# ---------------------------------------------------------------------------
RELAY_LOG="$HOME/.local/state/buzz-relay/relay.log"
echo "Starting buzz-relay (logs: ${RELAY_LOG})..."
nohup /usr/local/bin/buzz-relay-start </dev/null >>"${RELAY_LOG}" 2>&1 &
disown

echo "buzz-relay workspace ready. Buzz source: ${BUZZ_REPO_DIR}"

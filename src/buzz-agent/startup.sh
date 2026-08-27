#!/bin/bash
# Coder agent startup script for buzz-agent.
#
# Runs on every workspace start. Responsibilities:
#   1. Run agent-data-init to make this workspace's per-role bind-mounted
#      data root writable, lay out its persistent subdirectories, and
#      symlink ~/repos, ~/.config/buzz, and ~/.local/state/buzz-agent into
#      it (see agent-data-init for details; also independently runnable for
#      testing — see README.md "Validating this template").
#   2. Configure dotfiles as usual for this repository's templates.
#   3. Seed or update the Buzz source checkout at ~/repos/buzz (read-only
#      reference — this template runs prebuilt Sprig binaries, not a
#      from-source build) without overwriting dirty developer work.
#   4. Launch buzz-agent-start in the background with logs persisted under
#      the data root. If the agent's config file is incomplete, the wrapper
#      logs exactly what's missing and exits — it does not spin-loop.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

AGENT_DATA_ROOT="${AGENT_DATA_ROOT:-/home/coder/agent-data}"
/usr/local/bin/agent-data-init

if [ -n "${DOTFILES_URI:-}" ]; then
  echo "Installing dotfiles from ${DOTFILES_URI}..."
  coder dotfiles -y "${DOTFILES_URI}"
fi

# ---------------------------------------------------------------------------
# Seed or update the Buzz source checkout. Never overwrites uncommitted or
# unpushed developer work.
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
# Start buzz-acp (via buzz-agent-start) in the background, logs persisted
# under this workspace's per-role data root. This workspace has no coder_app
# and no published port: the agent's only network activity is its own
# outbound WebSocket connection to BUZZ_RELAY_URL.
# ---------------------------------------------------------------------------
AGENT_LOG="$AGENT_DATA_ROOT/logs/buzz-agent/agent.log"
echo "Starting buzz-agent-start (logs: ${AGENT_LOG})..."
nohup /usr/local/bin/buzz-agent-start </dev/null >>"${AGENT_LOG}" 2>&1 &
disown

echo "buzz-agent workspace ready. Buzz source: ${BUZZ_REPO_DIR}"
echo "If this is the first start, check ${AGENT_LOG} for identity/config guidance."

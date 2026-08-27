# ARGs used in a FROM must be declared before any FROM (global scope) — an
# ARG declared inside a stage (after some other FROM) is not visible to a
# later FROM's image-name interpolation.
ARG BUZZ_SPRIG_IMAGE=ghcr.io/block/buzz-sprig:sha-b622003
ARG BUZZ_IMAGE=ghcr.io/block/buzz:sha-b622003

# ---------------------------------------------------------------------------
# Base: Coder's official code-server image (Ubuntu Resolute)
# https://github.com/coder/code-server/pkgs/container/code-server
# ---------------------------------------------------------------------------
FROM ghcr.io/coder/code-server:resolute AS workspace-base

# ---------------------------------------------------------------------------
# Sprig multicall binary (buzz-acp, buzz-agent, buzz-dev-mcp, rg, tree, buzz,
# git-credential-nostr, git-sign-nostr) taken from the verified-public,
# multi-arch ghcr.io/block/buzz-sprig image for the pinned commit, rather
# than compiling Rust at image-build time. This mirrors upstream's own
# Dockerfile.sprig, which builds one `sprig` binary and symlinks every
# multicall tool name to it:
# https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/Dockerfile.sprig
# ---------------------------------------------------------------------------
FROM ${BUZZ_SPRIG_IMAGE} AS sprig-bin

# buzz-admin, taken from the relay image, used only as a local `generate-key`
# helper to mint this agent's own Nostr identity — this template never runs a
# relay or admin server from this image.
FROM ${BUZZ_IMAGE} AS buzz-bin

FROM workspace-base

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    PATH=/home/coder/.local/bin:${PATH}

# ---------------------------------------------------------------------------
# Base OS packages. No build toolchain: this image runs prebuilt Sprig
# binaries only (see decision note in README.md); no Postgres/Redis clients
# either, since buzz-agent has no sibling services and no Docker socket.
# ---------------------------------------------------------------------------
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash-completion \
        ca-certificates \
        curl \
        git \
        git-lfs \
        gnupg \
        iputils-ping \
        jq \
        less \
        netcat-openbsd \
        openssh-client \
        openssl \
        sudo \
        tmux \
        unzip \
        vim \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Sprig multicall binary and its multicall symlinks — installed exactly as
# upstream's own Dockerfile.sprig does it, so the resulting tool set matches
# the published sprig image byte-for-byte.
# ---------------------------------------------------------------------------
COPY --from=sprig-bin --chmod=0755 /usr/local/bin/sprig /usr/local/bin/sprig
RUN for name in \
      buzz-acp buzz-agent buzz-dev-mcp rg tree buzz \
      git-credential-nostr git-sign-nostr; do \
        ln -sf sprig "/usr/local/bin/${name}"; \
    done

# buzz-admin — used solely for local `buzz-admin generate-key` identity
# minting (see buzz-agent-start); not exposed as a service.
COPY --from=buzz-bin /usr/local/bin/buzz-admin /usr/local/bin/buzz-admin
RUN chmod 0755 /usr/local/bin/buzz-admin

# Sign commits made from this agent's identity with its Nostr key, matching
# upstream's own sprig image git configuration.
RUN git config --system gpg.format x509 \
    && git config --system gpg.x509.program /usr/local/bin/git-sign-nostr \
    && git config --system commit.gpgSign true \
    && git config --system tag.gpgSign true

# ---------------------------------------------------------------------------
# Configuration checker / start wrapper, and the per-role persistent data
# root bootstrapper it (and startup.sh) both depend on.
# ---------------------------------------------------------------------------
COPY --chown=root:root buzz-agent-start /usr/local/bin/buzz-agent-start
COPY --chown=root:root agent-data-init /usr/local/bin/agent-data-init
RUN chmod 0755 /usr/local/bin/buzz-agent-start /usr/local/bin/agent-data-init

# /home/coder/repos, /home/coder/.config/buzz, and /home/coder/.local/state/
# buzz-agent are NOT created here as real directories: at runtime they are
# idempotent symlinks (created by startup.sh, once the per-role host bind
# mount is writable) into subdirectories of /home/coder/agent-data — this
# workspace's dedicated, persistent, per-role data root (see main.tf and
# README.md "Persistence and lifecycle"). Provisioning them here would only
# create stale real directories that startup.sh has to detect and replace on
# first boot.
RUN mkdir -p /home/coder/agent-data \
    && chown coder:coder /home/coder/agent-data

USER coder

RUN printf '%s\n' \
        'if [[ $- == *i* && "$PWD" == "$HOME" ]]; then cd "$HOME/repos/buzz" 2>/dev/null || cd "$HOME"; fi' \
        >> /home/coder/.bashrc

WORKDIR /home/coder/repos

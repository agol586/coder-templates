# ARGs used in a FROM must be declared before any FROM (global scope) — an
# ARG declared inside a stage (after some other FROM) is not visible to a
# later FROM's image-name interpolation.
ARG BUZZ_IMAGE=ghcr.io/block/buzz:sha-b622003

# ---------------------------------------------------------------------------
# Base: Coder's official code-server image (Ubuntu Resolute)
# https://github.com/coder/code-server/pkgs/container/code-server
# ---------------------------------------------------------------------------
FROM ghcr.io/coder/code-server:resolute AS workspace-base

# ---------------------------------------------------------------------------
# Buzz relay/admin binaries, taken from the immutable public relay image
# instead of compiling the full Rust workspace at image-build time. The
# upstream image is itself a reproducible multi-stage build (see
# https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/Dockerfile); copying
# its stripped release binaries keeps this template's build fast and
# reproducible while still pinned to an immutable commit via BUZZ_IMAGE.
# Rebuilding from the checked-out source in ~/repos/buzz remains a documented
# manual option for development (see README.md).
# ---------------------------------------------------------------------------
FROM ${BUZZ_IMAGE} AS buzz-bin

FROM workspace-base

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    NVM_DIR=/home/coder/.nvm \
    RUSTUP_HOME=/home/coder/.rustup \
    CARGO_HOME=/home/coder/.cargo \
    PATH=/home/coder/.local/bin:/home/coder/.cargo/bin:${PATH}

# ---------------------------------------------------------------------------
# Base OS packages required to build, run, and operate Buzz:
#   - postgresql-client / redis-tools: dependency readiness checks
#   - build-essential/pkg-config/libssl-dev: optional local Rust rebuilds
#   - git/git-lfs: source checkout and Buzz's own git-backed repo storage
# ---------------------------------------------------------------------------
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash-completion \
        build-essential \
        ca-certificates \
        curl \
        git \
        git-lfs \
        gnupg \
        iputils-ping \
        jq \
        less \
        libssl-dev \
        netcat-openbsd \
        openssh-client \
        openssl \
        pkg-config \
        postgresql-client \
        redis-tools \
        ripgrep \
        sudo \
        tmux \
        tree \
        unzip \
        vim \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# buzz-relay / buzz-admin — copied from the pinned public relay image.
# ---------------------------------------------------------------------------
COPY --from=buzz-bin /usr/local/bin/buzz-relay /usr/local/bin/buzz-relay
COPY --from=buzz-bin /usr/local/bin/buzz-admin /usr/local/bin/buzz-admin
RUN chmod 0755 /usr/local/bin/buzz-relay /usr/local/bin/buzz-admin

# ---------------------------------------------------------------------------
# MinIO client (mc) — pinned to the same release upstream's compose bundle
# uses for its one-shot bucket bootstrap (minio/mc:RELEASE.2025-08-13T08-35-41Z),
# downloaded directly with checksum verification instead of a floating
# installer.
# https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/deploy/compose/compose.yml
# ---------------------------------------------------------------------------
ARG TARGETARCH
ARG MC_RELEASE=RELEASE.2025-08-13T08-35-41Z
ARG MC_SHA256_AMD64=01f866e9c5f9b87c2b09116fa5d7c06695b106242d829a8bb32990c00312e891
ARG MC_SHA256_ARM64=14c8c9616cfce4636add161304353244e8de383b2e2752c0e9dad01d4c27c12c
RUN mc_arch="${TARGETARCH:-$(dpkg --print-architecture)}" \
    && case "${mc_arch}" in \
        amd64) mc_sha256="${MC_SHA256_AMD64}" ;; \
        arm64) mc_sha256="${MC_SHA256_ARM64}" ;; \
        *) echo "Unsupported mc architecture: ${mc_arch}" >&2; exit 1 ;; \
    esac \
    && curl -fsSL \
        "https://github.com/minio/mc/releases/download/${MC_RELEASE}/mc.linux-${mc_arch}.${MC_RELEASE}" \
        -o /tmp/mc \
    && echo "${mc_sha256}  /tmp/mc" | sha256sum --check - \
    && install -m 0755 /tmp/mc /usr/local/bin/mc \
    && rm /tmp/mc

RUN mkdir -p /data/git && chown coder:coder /data/git

# ---------------------------------------------------------------------------
# Relay start wrapper (waits for dependencies, provisions the relay identity,
# runs migrations, and execs buzz-relay).
# ---------------------------------------------------------------------------
COPY --chown=root:root buzz-relay-start /usr/local/bin/buzz-relay-start
RUN chmod 0755 /usr/local/bin/buzz-relay-start

# ---------------------------------------------------------------------------
# User-level toolchain for developing/rebuilding Buzz from source.
# Rust's version is pinned by the checked-out repo's own rust-toolchain.toml
# (rustup reads it automatically); Node's LTS follows the same nvm pattern
# already used by the other templates in this repository.
# ---------------------------------------------------------------------------
USER coder

RUN curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh \
    && sh /tmp/rustup-init.sh -y --default-toolchain none --profile minimal \
    && rm /tmp/rustup-init.sh

RUN curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh -o /tmp/install-nvm.sh \
    && PROFILE=/dev/null bash /tmp/install-nvm.sh \
    && rm /tmp/install-nvm.sh \
    && . "${NVM_DIR}/nvm.sh" \
    && nvm install 24 \
    && nvm alias default 24 \
    && corepack enable \
    && printf '%s\n' \
        'export NVM_DIR="$HOME/.nvm"' \
        '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' \
        'export RUSTUP_HOME="$HOME/.rustup"' \
        'export CARGO_HOME="$HOME/.cargo"' \
        'export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"' \
        'if [[ $- == *i* && "$PWD" == "$HOME" ]]; then cd "$HOME/repos/buzz" 2>/dev/null || cd "$HOME"; fi' \
        >> /home/coder/.bashrc

# just — pinned release tarball with checksum verification (no floating
# install script), used for Buzz's own `just relay` / `just build-relay`
# recipes when rebuilding from source.
ARG JUST_VERSION=1.43.0
RUN just_arch="$(dpkg --print-architecture)" \
    && case "${just_arch}" in \
        amd64) just_target="x86_64-unknown-linux-musl" ;; \
        arm64) just_target="aarch64-unknown-linux-musl" ;; \
        *) echo "Unsupported just architecture: ${just_arch}" >&2; exit 1 ;; \
    esac \
    && just_tarball="just-${JUST_VERSION}-${just_target}.tar.gz" \
    && curl -fsSL \
        "https://github.com/casey/just/releases/download/${JUST_VERSION}/${just_tarball}" \
        -o "/tmp/${just_tarball}" \
    && curl -fsSL \
        "https://github.com/casey/just/releases/download/${JUST_VERSION}/SHA256SUMS" \
        -o /tmp/just.SHA256SUMS \
    && (cd /tmp && grep -F " ${just_tarball}" just.SHA256SUMS | sha256sum --check --strict - || \
        (echo "just checksum verification failed" >&2; exit 1)) \
    && mkdir -p /tmp/just-extract \
    && tar -C /tmp/just-extract -xzf "/tmp/${just_tarball}" just \
    && install -D -m 0755 /tmp/just-extract/just /home/coder/.local/bin/just \
    && rm -rf "/tmp/${just_tarball}" /tmp/just.SHA256SUMS /tmp/just-extract

RUN mkdir -p /home/coder/repos /home/coder/.local/bin /home/coder/.config/buzz-relay /home/coder/.local/state/buzz-relay \
    && chmod 700 /home/coder/.config/buzz-relay

WORKDIR /home/coder/repos

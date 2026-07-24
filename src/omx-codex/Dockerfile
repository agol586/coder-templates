# ---------------------------------------------------------------------------
# Base: Coder's official code-server image (Ubuntu Resolute)
# https://github.com/coder/code-server/pkgs/container/code-server
# ---------------------------------------------------------------------------
FROM ghcr.io/coder/code-server:resolute

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    CODEGRAPH_TELEMETRY=0 \
    NVM_DIR=/home/coder/.nvm \
    GOPATH=/home/coder/go \
    PATH=/home/coder/.local/bin:/home/coder/go/bin:/usr/local/go/bin:${PATH}

# ---------------------------------------------------------------------------
# Base development toolchain
# ---------------------------------------------------------------------------
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash-completion \
        bubblewrap \
        build-essential \
        ca-certificates \
        curl \
        dnsutils \
        fd-find \
        file \
        fzf \
        git \
        git-lfs \
        gnupg \
        iputils-ping \
        jq \
        less \
        locales \
        man-db \
        netcat-openbsd \
        openssh-client \
        pkg-config \
        python3 \
        python3-pip \
        python3-venv \
        ripgrep \
        shellcheck \
        sqlite3 \
        sudo \
        tmux \
        tree \
        unzip \
        vim \
        wget \
        zip \
    && rm -rf /var/lib/apt/lists/*

COPY --chown=coder:coder code-server-start.sh /usr/local/bin/code-server-start
RUN chmod +x /usr/local/bin/code-server-start

# ---------------------------------------------------------------------------
# Latest stable Go release, with checksum verification
# https://go.dev/dl/
# ---------------------------------------------------------------------------
ARG TARGETARCH
RUN go_arch="${TARGETARCH:-$(dpkg --print-architecture)}" \
    && case "${go_arch}" in \
        amd64) go_arch="amd64" ;; \
        arm64) go_arch="arm64" ;; \
        *) echo "Unsupported Go architecture: ${go_arch}" >&2; exit 1 ;; \
    esac \
    && go_version="$(curl -fsSL 'https://go.dev/VERSION?m=text' | sed -n '1p')" \
    && archive="${go_version}.linux-${go_arch}.tar.gz" \
    && checksum="$(curl -fsSL 'https://go.dev/dl/?mode=json' \
        | jq -r --arg archive "${archive}" \
          '[.[].files[] | select(.filename == $archive) | .sha256][0] // empty')" \
    && test -n "${checksum}" \
    && curl -fsSL "https://go.dev/dl/${archive}" -o "/tmp/${archive}" \
    && echo "${checksum}  /tmp/${archive}" | sha256sum --check - \
    && rm -rf /usr/local/go \
    && tar -C /usr/local -xzf "/tmp/${archive}" \
    && rm "/tmp/${archive}"

# ---------------------------------------------------------------------------
# User-level developer tools
# ---------------------------------------------------------------------------
USER coder

# nvm and the current Node.js LTS.
RUN curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh -o /tmp/install-nvm.sh \
    && PROFILE=/dev/null bash /tmp/install-nvm.sh \
    && rm /tmp/install-nvm.sh \
    && . "${NVM_DIR}/nvm.sh" \
    && nvm install --lts \
    && nvm alias default 'lts/*' \
    && npm install --global \
        eslint \
        oh-my-codex \
        prettier \
        ts-node \
        typescript \
        typescript-language-server \
    && printf '%s\n' \
        'export NVM_DIR="$HOME/.nvm"' \
        '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"' \
        '[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"' \
        'export PATH="$HOME/.local/bin:$HOME/go/bin:/usr/local/go/bin:$PATH"' \
        'if [[ $- == *i* && "$PWD" == "$HOME" ]]; then cd "$HOME/repos"; fi' \
        >> /home/coder/.bashrc

# OpenAI Codex native CLI.
RUN curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/install-codex.sh \
    && CODEX_NON_INTERACTIVE=true CODEX_INSTALL_DIR=/home/coder/.local/bin sh /tmp/install-codex.sh \
    && rm /tmp/install-codex.sh

# CodeGraph standalone bundle includes its own Node runtime.
RUN curl -fsSL https://raw.githubusercontent.com/colbymchenry/codegraph/main/install.sh \
        -o /tmp/install-codegraph.sh \
    && CODEGRAPH_INSTALL_DIR=/home/coder/.codegraph \
       CODEGRAPH_BIN_DIR=/home/coder/.local/bin \
       sh /tmp/install-codegraph.sh \
    && rm /tmp/install-codegraph.sh

# uv and GitHub Spec Kit's specify CLI.
RUN curl -LsSf https://astral.sh/uv/install.sh -o /tmp/install-uv.sh \
    && UV_INSTALL_DIR=/home/coder/.local/bin sh /tmp/install-uv.sh \
    && rm /tmp/install-uv.sh \
    && uv tool install specify-cli --from git+https://github.com/github/spec-kit.git

RUN mkdir -p /home/coder/repos /home/coder/go/bin \
    && ln -sf /usr/bin/fdfind /home/coder/.local/bin/fd

WORKDIR /home/coder/repos

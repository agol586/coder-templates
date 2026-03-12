ARG GO_VERSION=1.22

# ---------------------------------------------------------------------------
# Base: Official Go image
# ---------------------------------------------------------------------------
FROM golang:${GO_VERSION}-bookworm

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# ---------------------------------------------------------------------------
# System packages
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Editors & utilities
    git \
    curl \
    wget \
    vim \
    nano \
    unzip \
    zip \
    jq \
    htop \
    sudo \
    ca-certificates \
    gnupg \
    lsb-release \
    # Build essentials
    build-essential \
    pkg-config \
    # Networking
    dnsutils \
    iputils-ping \
    net-tools \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# code-server (VS Code in the browser)
# ---------------------------------------------------------------------------
RUN curl -fsSL https://code-server.dev/install.sh | sh

# ---------------------------------------------------------------------------
# Create the coder user
# ---------------------------------------------------------------------------
RUN useradd --create-home --shell /bin/bash --uid 1000 --groups sudo coder \
    && echo "coder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/coder \
    && chmod 0440 /etc/sudoers.d/coder

# ---------------------------------------------------------------------------
# Go environment (accessible to the coder user)
# ---------------------------------------------------------------------------
ENV GOPATH=/home/coder/go
ENV PATH="${PATH}:${GOPATH}/bin"
RUN mkdir -p /home/coder/go && chown -R coder:coder /home/coder/go

# ---------------------------------------------------------------------------
# code-server startup helper (runs as coder user via the Coder agent startup
# script, not at container boot – the container starts the Coder agent only)
# ---------------------------------------------------------------------------
COPY --chown=coder:coder code-server-start.sh /usr/local/bin/code-server-start
RUN chmod +x /usr/local/bin/code-server-start

USER coder
WORKDIR /home/coder

# ---------------------------------------------------------------------------
# Base: Coder's official code-server image (Ubuntu Resolute)
# https://github.com/coder/code-server/pkgs/container/code-server
# code-server is pre-installed in this image.
# ---------------------------------------------------------------------------
FROM ghcr.io/coder/code-server:resolute

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# ---------------------------------------------------------------------------
# Go toolchain (latest stable)
# https://go.dev/dl/
# ---------------------------------------------------------------------------
USER root
RUN GO_LATEST=$(curl -fsSL https://go.dev/VERSION?m=text) \
    && curl -fsSL "https://go.dev/dl/${GO_LATEST}.linux-amd64.tar.gz" | tar -xz -C /usr/local
ENV PATH="/usr/local/go/bin:${PATH}"
ENV GOPATH="/home/coder/go"
RUN mkdir -p "${GOPATH}/bin" && chown -R coder:coder "${GOPATH}"

# ---------------------------------------------------------------------------
# code-server startup helper (invoked by the Coder agent startup script)
# ---------------------------------------------------------------------------
COPY --chown=coder:coder code-server-start.sh /usr/local/bin/code-server-start
RUN chmod +x /usr/local/bin/code-server-start

USER coder
WORKDIR /home/coder

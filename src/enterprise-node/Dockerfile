# ---------------------------------------------------------------------------
# Base: Coder's official code-server image (Ubuntu Resolute)
# https://github.com/coder/code-server/pkgs/container/code-server
# code-server is pre-installed in this image.
# ---------------------------------------------------------------------------
FROM ghcr.io/coder/code-server:resolute

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# ---------------------------------------------------------------------------
# code-server startup helper (invoked by the Coder agent startup script)
# ---------------------------------------------------------------------------
USER root
COPY --chown=coder:coder code-server-start.sh /usr/local/bin/code-server-start
RUN chmod +x /usr/local/bin/code-server-start

# ---------------------------------------------------------------------------
# nvm + Node.js LTS (installed as coder user)
# https://github.com/nvm-sh/nvm
# ---------------------------------------------------------------------------
USER coder
ENV NVM_DIR=/home/coder/.nvm
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash \
    && . "$NVM_DIR/nvm.sh" \
    && nvm install --lts \
    && nvm alias default 'lts/*' \
    && echo '. "$NVM_DIR/nvm.sh"' >> /home/coder/.bashrc

WORKDIR /home/coder

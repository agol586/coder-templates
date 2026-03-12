# ---------------------------------------------------------------------------
# Base: Coder's official enterprise base image
# ---------------------------------------------------------------------------
FROM codercom/enterprise-base:latest

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# ---------------------------------------------------------------------------
# code-server (VS Code in the browser)
# ---------------------------------------------------------------------------
USER root
RUN curl -fsSL https://code-server.dev/install.sh | sh

# ---------------------------------------------------------------------------
# code-server startup helper (invoked by the Coder agent startup script)
# ---------------------------------------------------------------------------
COPY --chown=coder:coder code-server-start.sh /usr/local/bin/code-server-start
RUN chmod +x /usr/local/bin/code-server-start

USER coder
WORKDIR /home/coder

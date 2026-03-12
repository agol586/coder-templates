# Enterprise Base Workspace

A production-ready [Coder](https://coder.com) general-purpose template for enterprise development environments.

## Features

| Feature | Details |
|---------|---------|
| **Base image** | [`codercom/enterprise-base:latest`](https://hub.docker.com/r/codercom/enterprise-base) |
| **IDE** | VS Code Web (code-server) available in the browser |
| **Dotfiles** | Optional personal dotfiles repo cloned at startup |
| **Persistent home** | Docker volume mounted at `/home/coder` |
| **Git identity** | Automatically configured from Coder user profile |
| **Resources** | CPU (1–8 cores) and memory (2–16 GB) selectable at creation |

## Prerequisites

- A running [Coder](https://coder.com/docs/install) deployment
- Docker available on the Coder provisioner host

## Quick Start

### 1. Install the Coder CLI

```bash
# Linux / macOS
curl -L https://coder.com/install.sh | sh

# Windows (winget)
winget install Coder.Coder
```

### 2. Log in

```bash
coder login https://<your-coder-url>
```

### 3. Create the template

```bash
git clone https://github.com/agol586/coder-templates.git
cd coder-templates
coder templates create enterprise-base --directory enterprise-base
```

### 4. Create a workspace

```bash
coder create my-workspace --template enterprise-base
```

Or create a workspace through the Coder web UI.

## Connecting to Your Workspace

### VS Code Web
Click the **VS Code Web** button from the workspace page. A full VS Code experience opens in your browser.

### SSH
```bash
coder ssh my-workspace
```

### Terminal (web)
Click the **Terminal** icon in the Coder web UI.

### VS Code Desktop
Install the [Coder extension](https://marketplace.visualstudio.com/items?itemName=coder.coder-remote) for VS Code, then connect through the Remote Explorer panel.

## Template Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `cpu` | Number of CPU cores (1–8) | `2` |
| `memory` | RAM in GB (2–16) | `4` |
| `dotfiles_uri` | Git repo URI for personal dotfiles | *(empty)* |

## Customization

### Dockerfile

The `Dockerfile` in this directory layers on top of `codercom/enterprise-base:latest`. You can extend it to
add company-specific CA certificates, internal tooling, or additional packages:

```dockerfile
FROM codercom/enterprise-base:latest

# Example: add a corporate CA certificate
USER root
COPY corp-ca.crt /usr/local/share/ca-certificates/corp-ca.crt
RUN update-ca-certificates

# Example: install additional tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
  && rm -rf /var/lib/apt/lists/*

USER coder
```

### Startup Script

Edit the `startup_script` block inside `main.tf` to install additional tools or
run company-specific initialization steps.

## Architecture

```
Coder deployment
└── Docker (on provisioner host)
    └── Container: coder-<owner>-<workspace>
        ├── /home/coder        ← persistent Docker volume
        │   └── <projects>/
        └── code-server        ← VS Code Web on :13337
```

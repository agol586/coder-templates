# Enterprise Node.js Workspace

A production-ready [Coder](https://coder.com) template for Node.js development in enterprise environments.

## Features

| Feature | Details |
|---------|---------|
| **Base image** | [`codercom/enterprise-node:latest`](https://hub.docker.com/r/codercom/enterprise-node) |
| **IDE** | VS Code Web (code-server) available in the browser |
| **Language server** | `typescript-language-server` installed automatically |
| **Linter** | `eslint` installed automatically |
| **Formatter** | `prettier` installed automatically |
| **TypeScript runner** | `ts-node` installed automatically |
| **npm registry** | Configurable npm registry (enterprise registry support) |
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
coder templates create enterprise-node --directory enterprise-node
```

### 4. Create a workspace

```bash
coder create my-node-workspace --template enterprise-node
```

Or create a workspace through the Coder web UI.

## Connecting to Your Workspace

### VS Code Web
Click the **VS Code Web** button from the workspace page. A full VS Code experience opens in your browser.

### SSH
```bash
coder ssh my-node-workspace
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
| `npm_registry` | npm registry URL for package installation | `https://registry.npmjs.org` |
| `dotfiles_uri` | Git repo URI for personal dotfiles | *(empty)* |

### Enterprise npm Registry

To route npm package downloads through an internal registry, set `npm_registry` to your
enterprise registry URL when creating a workspace:

```bash
coder create my-node-workspace \
  --template enterprise-node \
  --parameter "npm_registry=https://npm.corp.example.com"
```

## Pre-installed Node.js Tools

The following tools are installed at workspace startup:

| Tool | Purpose |
|------|---------|
| [`typescript-language-server`](https://github.com/typescript-language-server/typescript-language-server) | TypeScript/JavaScript language server |
| [`eslint`](https://eslint.org/) | JavaScript/TypeScript linter |
| [`prettier`](https://prettier.io/) | Code formatter |
| [`ts-node`](https://typestrong.org/ts-node/) | TypeScript execution engine for Node.js |

## Customization

### Dockerfile

The `Dockerfile` in this directory layers on top of `codercom/enterprise-node:latest`. You can extend it to
add company-specific CA certificates, internal tooling, or additional packages:

```dockerfile
FROM codercom/enterprise-node:latest

# Example: add a corporate CA certificate
USER root
COPY corp-ca.crt /usr/local/share/ca-certificates/corp-ca.crt
RUN update-ca-certificates

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

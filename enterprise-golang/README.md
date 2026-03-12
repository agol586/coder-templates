# Enterprise Go Workspace

A production-ready [Coder](https://coder.com) template for Go (Golang) development in enterprise environments.

## Features

| Feature | Details |
|---------|---------|
| **Base image** | [`codercom/enterprise-golang:latest`](https://hub.docker.com/r/codercom/enterprise-golang) |
| **IDE** | VS Code Web (code-server) available in the browser |
| **Language server** | `gopls` installed automatically |
| **Linter** | `golangci-lint` installed automatically |
| **Debugger** | Delve (`dlv`) installed automatically |
| **Import organizer** | `goimports` installed automatically |
| **Static analysis** | `staticcheck` installed automatically |
| **Module proxy** | Configurable `GOPROXY` (enterprise proxy support) |
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
coder templates create enterprise-golang --directory enterprise-golang
```

### 4. Create a workspace

```bash
coder create my-go-workspace --template enterprise-golang
```

Or create a workspace through the Coder web UI.

## Connecting to Your Workspace

### VS Code Web
Click the **VS Code Web** button from the workspace page. A full VS Code experience opens in your browser.

### SSH
```bash
coder ssh my-go-workspace
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
| `goproxy` | `GOPROXY` URL for module resolution | `https://proxy.golang.org,direct` |
| `dotfiles_uri` | Git repo URI for personal dotfiles | *(empty)* |

### Enterprise Module Proxy

To route Go module downloads through an internal proxy, set `goproxy` to your
enterprise proxy URL when creating a workspace:

```bash
coder create my-go-workspace \
  --template enterprise-golang \
  --parameter "goproxy=https://goproxy.corp.example.com,direct"
```

## Pre-installed Go Tools

The following tools are installed at workspace startup:

| Tool | Purpose |
|------|---------|
| [`gopls`](https://pkg.go.dev/golang.org/x/tools/gopls) | Official Go language server |
| [`golangci-lint`](https://golangci-lint.run/) | Fast Go linter runner |
| [`dlv`](https://github.com/go-delve/delve) | Go debugger |
| [`goimports`](https://pkg.go.dev/golang.org/x/tools/cmd/goimports) | Import organization tool |
| [`staticcheck`](https://staticcheck.dev/) | Advanced static analysis |

## Customization

### Dockerfile

The `Dockerfile` in this directory layers on top of `codercom/enterprise-golang:latest`. You can extend it to
add company-specific CA certificates, internal tooling, or additional packages:

```dockerfile
FROM codercom/enterprise-golang:latest

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
        │   ├── go/            ← GOPATH
        │   └── <projects>/
        └── code-server        ← VS Code Web on :13337
```

## License

See [LICENSE](../LICENSE) in the repository root.

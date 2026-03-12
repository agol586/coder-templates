terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

provider "docker" {}

provider "coder" {}

# --------------------------------------------------------------------------- #
# Parameters
# --------------------------------------------------------------------------- #

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU Cores"
  description  = "Number of CPU cores for the workspace container."
  type         = "number"
  default      = "2"
  mutable      = true
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/cpu-3.svg"

  validation {
    min = 1
    max = 8
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "Amount of memory (RAM) in GB for the workspace container."
  type         = "number"
  default      = "4"
  mutable      = true
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/memory.svg"

  validation {
    min = 2
    max = 16
  }
}

data "coder_parameter" "goproxy" {
  name         = "goproxy"
  display_name = "Go Module Proxy"
  description  = "GOPROXY URL for resolving Go modules. Use 'direct' to bypass any proxy, or set an enterprise proxy URL."
  type         = "string"
  default      = "https://proxy.golang.org,direct"
  mutable      = true
  icon         = "https://cdn.jsdelivr.net/gh/devicons/devicon/icons/go/go-original-wordmark.svg"
}

data "coder_parameter" "dotfiles_uri" {
  name         = "dotfiles_uri"
  display_name = "Dotfiles URI"
  description  = "Git repository URI containing your personal dotfiles. Leave blank to skip."
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "https://raw.githubusercontent.com/coder/coder/main/site/static/icon/terminal.svg"
}

# --------------------------------------------------------------------------- #
# Workspace metadata
# --------------------------------------------------------------------------- #

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# --------------------------------------------------------------------------- #
# Agent
# --------------------------------------------------------------------------- #

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"

  env = {
    GOPROXY      = data.coder_parameter.goproxy.value
    GOPATH       = "/home/coder/go"
    GOMODCACHE   = "/home/coder/go/pkg/mod"
    GIT_AUTHOR_NAME     = data.coder_workspace_owner.me.full_name
    GIT_COMMITTER_NAME  = data.coder_workspace_owner.me.full_name
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

  startup_script = <<-EOT
    #!/bin/bash
    set -euo pipefail

    # Install / upgrade Go tooling
    echo "→ Installing Go development tools..."
    export GOPATH="$HOME/go"
    export PATH="$PATH:$GOPATH/bin:/usr/local/go/bin"

    # gopls – Go language server
    go install golang.org/x/tools/gopls@latest 2>/dev/null || true

    # golangci-lint – linter
    if ! command -v golangci-lint &>/dev/null; then
      curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh \
        | sh -s -- -b "$GOPATH/bin" 2>/dev/null || true
    fi

    # dlv – Delve debugger
    go install github.com/go-delve/delve/cmd/dlv@latest 2>/dev/null || true

    # goimports – import organizer
    go install golang.org/x/tools/cmd/goimports@latest 2>/dev/null || true

    # staticcheck – static analysis
    go install honnef.co/go/tools/cmd/staticcheck@latest 2>/dev/null || true

    # Install dotfiles if provided
    if [ -n "${DOTFILES_URI:-}" ]; then
      echo "→ Cloning dotfiles from $DOTFILES_URI..."
      coder dotfiles -y "$DOTFILES_URI" 2>/dev/null || true
    fi

    # Start code-server (VS Code Web)
    echo "→ Starting code-server..."
    code-server-start &

    echo "→ Startup complete."
  EOT

  startup_script_timeout = 300

  metadata {
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage"
    key          = "memory_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Disk Usage"
    key          = "disk_usage"
    script       = "coder stat disk --path /home/coder"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Go Version"
    key          = "go_version"
    script       = "/usr/local/go/bin/go version | awk '{print $3}'"
    interval     = 3600
    timeout      = 5
  }
}

# --------------------------------------------------------------------------- #
# VS Code Web (code-server)
# --------------------------------------------------------------------------- #

resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code Web"
  url          = "http://localhost:13337/?folder=/home/coder"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url      = "http://localhost:13337/healthz"
    interval = 5
    threshold = 6
  }
}

# --------------------------------------------------------------------------- #
# Docker resources
# --------------------------------------------------------------------------- #

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-home"

  lifecycle {
    ignore_changes = all
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_image" "golang" {
  name         = "coder-enterprise-golang:local"
  keep_locally = true

  build {
    context    = path.module
    dockerfile = "Dockerfile"
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.golang.image_id
  name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"

  hostname = data.coder_workspace.me.name

  cpu_shares = data.coder_parameter.cpu.value * 1024
  memory     = data.coder_parameter.memory.value * 1024

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "GOPROXY=${data.coder_parameter.goproxy.value}",
    "DOTFILES_URI=${data.coder_parameter.dotfiles_uri.value}",
  ]

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost/", "host.docker.internal")]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
}

# --------------------------------------------------------------------------- #
# Metadata (cost / workspace info)
# --------------------------------------------------------------------------- #

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id
  daily_cost  = 10

  item {
    key   = "Base Image"
    value = "codercom/enterprise-golang:latest"
  }
  item {
    key   = "CPU Cores"
    value = data.coder_parameter.cpu.value
  }
  item {
    key   = "Memory"
    value = "${data.coder_parameter.memory.value} GB"
  }
  item {
    key   = "GOPROXY"
    value = data.coder_parameter.goproxy.value
  }
}

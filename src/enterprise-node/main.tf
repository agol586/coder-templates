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

data "coder_parameter" "npm_registry" {
  name         = "npm_registry"
  display_name = "npm Registry"
  description  = "npm registry URL for installing packages. Use the default public registry or set an enterprise registry URL."
  type         = "string"
  default      = "https://registry.npmjs.org"
  mutable      = true
  icon         = "https://cdn.jsdelivr.net/gh/devicons/devicon/icons/nodejs/nodejs-original.svg"
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
    NPM_CONFIG_REGISTRY = data.coder_parameter.npm_registry.value
    GIT_AUTHOR_NAME     = data.coder_workspace_owner.me.full_name
    GIT_COMMITTER_NAME  = data.coder_workspace_owner.me.full_name
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

  startup_script = file("${path.module}/startup.sh")

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
    display_name = "Node Version"
    key          = "node_version"
    script       = "node --version 2>/dev/null || echo 'unknown'"
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
    url       = "http://localhost:13337/healthz"
    interval  = 5
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

resource "docker_image" "node" {
  name         = "coder-enterprise-node:local"
  keep_locally = true

  build {
    context    = path.module
    dockerfile = "Dockerfile"
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.node.image_id
  name  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"

  hostname = data.coder_workspace.me.name

  cpu_shares = data.coder_parameter.cpu.value * 1024
  memory     = data.coder_parameter.memory.value * 1024

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "NPM_CONFIG_REGISTRY=${data.coder_parameter.npm_registry.value}",
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
    value = "codercom/enterprise-node:latest"
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
    key   = "npm Registry"
    value = data.coder_parameter.npm_registry.value
  }
}

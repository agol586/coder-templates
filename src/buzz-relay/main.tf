terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

provider "docker" {}
provider "coder" {}
provider "random" {}

# --------------------------------------------------------------------------- #
# Parameters
# --------------------------------------------------------------------------- #

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU Cores"
  description  = "Number of CPU cores for the workspace container. Sibling PostgreSQL/Redis/MinIO containers use fixed, modest limits (see README.md)."
  type         = "number"
  default      = "4"
  mutable      = true
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/cpu-3.svg"

  validation {
    min = 2
    max = 16
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "Amount of memory (RAM) in GB for the workspace container."
  type         = "number"
  default      = "8"
  mutable      = true
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/memory.svg"

  validation {
    min = 4
    max = 32
  }
}

data "coder_parameter" "dotfiles_uri" {
  name         = "dotfiles_uri"
  display_name = "Dotfiles URI"
  description  = "Git repository URI containing personal dotfiles. Leave blank to skip."
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "https://raw.githubusercontent.com/coder/coder/main/site/static/icon/terminal.svg"
}

data "coder_parameter" "buzz_ref" {
  name         = "buzz_ref"
  display_name = "Buzz Commit"
  description  = <<-EOT
    Immutable Buzz commit to run. Selects the public ghcr.io/block/buzz:sha-<7>
    relay image and the Buzz source checkout in ~/repos/buzz. Do not point
    this at a floating branch.
  EOT
  type         = "string"
  default      = "b622003f74aa5bf9b659786452813299a25e4897"
  mutable      = true

  validation {
    regex = "^[0-9a-fA-F]{7,40}$"
    error = "buzz_ref must be a 7-40 character hex commit SHA."
  }
}

data "coder_parameter" "relay_public_url" {
  name         = "relay_public_url"
  display_name = "Relay Public URL"
  description  = <<-EOT
    The wss:// URL that Buzz clients use to reach this relay through the
    separately configured external reverse proxy (TLS termination, WebSocket
    upgrade, and unchanged forwarding to container port 3000 are deployment
    prerequisites — see README.md). Buzz advertises this exact value as
    RELAY_URL.
  EOT
  type         = "string"
  mutable      = true

  validation {
    # Coder supplies an empty sentinel while importing a template to detect
    # persistent resources. Real workspace values remain constrained to wss.
    regex = "^$|^wss://[a-zA-Z0-9.-]+(:[0-9]+)?$"
    error = "relay_public_url must look like wss://buzz.example.com (no path, no trailing slash)."
  }
}

data "coder_parameter" "relay_owner_pubkey" {
  name         = "relay_owner_pubkey"
  display_name = "Relay Owner Pubkey"
  description  = <<-EOt
    Optional 64-character hex Nostr pubkey for the relay owner. When set,
    BUZZ_REQUIRE_RELAY_MEMBERSHIP is enabled (closed relay mode). Leave blank
    to run an open relay.
  EOt
  type         = "string"
  default      = ""
  mutable      = true

  validation {
    regex = "^([0-9a-fA-F]{64})?$"
    error = "relay_owner_pubkey must be empty or exactly 64 hex characters."
  }
}

data "coder_parameter" "minio_bucket" {
  name         = "minio_bucket"
  display_name = "Media/Git Bucket"
  description  = "MinIO bucket used for Buzz media and git objects (BUZZ_S3_BUCKET)."
  type         = "string"
  default      = "buzz-media"
  mutable      = true

  validation {
    regex = "^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$"
    error = "minio_bucket must be a valid lowercase bucket name (3-63 chars, alphanumeric and hyphens)."
  }
}

data "coder_parameter" "relay_host_port" {
  name         = "relay_host_port"
  display_name = "Relay Host Port"
  description  = <<-EOT
    Provisioner-host port published to container port 3000. Point the
    external reverse proxy's upstream at this host's address on this port.
    Only the relay's app port is published to the host — PostgreSQL, Redis,
    and MinIO stay on the private per-workspace Docker network.
  EOT
  type         = "number"
  default      = "3000"
  mutable      = false

  validation {
    min = 1024
    max = 65535
  }
}

data "coder_parameter" "rust_log" {
  name         = "rust_log"
  display_name = "RUST_LOG"
  description  = "Log filter passed to buzz-relay."
  type         = "string"
  default      = "buzz_relay=info,buzz_db=info,buzz_auth=info,buzz_pubsub=info,tower_http=info"
  mutable      = true
}

# --------------------------------------------------------------------------- #
# Workspace metadata
# --------------------------------------------------------------------------- #

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  buzz_ref_short   = substr(data.coder_parameter.buzz_ref.value, 0, 7)
  buzz_image       = "ghcr.io/block/buzz:sha-${local.buzz_ref_short}"
  relay_host       = replace(data.coder_parameter.relay_public_url.value, "wss://", "")
  media_base_url   = "https://${local.relay_host}/media"
  cors_origin      = "https://${local.relay_host}"
  has_owner_pubkey = data.coder_parameter.relay_owner_pubkey.value != ""
  resource_prefix  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
}

# --------------------------------------------------------------------------- #
# Generated infrastructure secrets.
#
# These are workspace-infrastructure credentials (PostgreSQL, Redis, MinIO),
# not Buzz identity material. They live only in Terraform state (marked
# sensitive by the random provider) and container environments — never in a
# coder_parameter, coder_metadata item, or startup log. Alphanumeric-only so
# they can be embedded directly in DATABASE_URL/REDIS_URL without percent-
# encoding. Buzz's own signing identity is generated separately, at runtime,
# into a 0600 file outside Terraform state (see buzz-relay-start).
# --------------------------------------------------------------------------- #

resource "random_password" "postgres" {
  length  = 32
  special = false
}

resource "random_password" "redis" {
  length  = 32
  special = false
}

resource "random_password" "minio_access_key" {
  length  = 20
  special = false
}

resource "random_password" "minio_secret_key" {
  length  = 40
  special = false
}

# --------------------------------------------------------------------------- #
# Agent
# --------------------------------------------------------------------------- #

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

  startup_script = file("${path.module}/startup.sh")

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
    display_name = "Buzz Commit"
    key          = "buzz_commit"
    script       = "printf '%s' \"$${BUZZ_REF:-unknown}\""
    interval     = 3600
    timeout      = 5
  }

  metadata {
    display_name = "Relay Readiness"
    key          = "relay_readiness"
    script       = <<-EOT
      #!/bin/bash
      if curl -fsS -o /dev/null -m 3 http://localhost:8080/_readiness; then
        echo "ready"
      else
        echo "not ready"
      fi
    EOT
    interval     = 30
    timeout      = 5
  }

  metadata {
    display_name = "Dependency Health"
    key          = "dependency_health"
    script       = <<-EOT
      #!/bin/bash
      status=()
      pg_isready -h postgres -p 5432 -U buzz -d buzz >/dev/null 2>&1 && status+=("postgres:up") || status+=("postgres:down")
      redis-cli -h redis -p 6379 -a "$${REDIS_PASSWORD:-}" --no-auth-warning ping 2>/dev/null | grep -q PONG && status+=("redis:up") || status+=("redis:down")
      curl -fsS -o /dev/null -m 3 http://minio:9000/minio/health/live 2>/dev/null && status+=("minio:up") || status+=("minio:down")
      printf '%s' "$${status[*]}"
    EOT
    interval     = 60
    timeout      = 10
  }
}

module "vscode-web" {
  count          = data.coder_workspace.me.start_count
  source         = "registry.coder.com/coder/vscode-web/coder"
  version        = "1.5.0"
  agent_id       = coder_agent.main.id
  folder         = "/home/coder/repos/buzz"
  accept_license = true
}

# --------------------------------------------------------------------------- #
# Coder apps — owner-authenticated access to the relay running inside this
# workspace. These are distinct from the external public domain: the public
# domain is served by a separately configured reverse proxy that forwards
# straight to container port 3000 (see relay_host_port and README.md), and it
# must not add any authentication layer in front of Buzz's own NIP-42/NIP-98.
# --------------------------------------------------------------------------- #

resource "coder_app" "buzz" {
  agent_id     = coder_agent.main.id
  slug         = "buzz"
  display_name = "Buzz Relay"
  icon         = "${data.coder_workspace.me.access_url}/emojis/1f41d.png"
  url          = "http://localhost:3000"
  share        = "owner"
  subdomain    = true
  order        = 0

  healthcheck {
    url       = "http://localhost:8080/_readiness"
    interval  = 10
    threshold = 6
  }
}

resource "coder_app" "readiness" {
  agent_id     = coder_agent.main.id
  slug         = "readiness"
  display_name = "Relay Readiness"
  icon         = "${data.coder_workspace.me.access_url}/emojis/2705.png"
  url          = "http://localhost:8080/_readiness"
  share        = "owner"
  subdomain    = true
  order        = 1
}

resource "coder_app" "metrics" {
  agent_id     = coder_agent.main.id
  slug         = "metrics"
  display_name = "Relay Metrics"
  icon         = "${data.coder_workspace.me.access_url}/emojis/1f4c8.png"
  url          = "http://localhost:9102/metrics"
  share        = "owner"
  subdomain    = true
  order        = 2
}

# --------------------------------------------------------------------------- #
# Docker resources
# --------------------------------------------------------------------------- #

resource "docker_network" "buzz" {
  name     = "${local.resource_prefix}-net"
  driver   = "bridge"
  internal = false

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
}

resource "docker_volume" "home_volume" {
  name = "${local.resource_prefix}-home"

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

resource "docker_volume" "postgres_data" {
  name = "${local.resource_prefix}-postgres-data"

  lifecycle {
    ignore_changes = all
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "com.buzz.volume"
    value = "postgres"
  }
}

resource "docker_volume" "minio_data" {
  name = "${local.resource_prefix}-minio-data"

  lifecycle {
    ignore_changes = all
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "com.buzz.volume"
    value = "minio"
  }
}

resource "docker_volume" "git_cache" {
  name = "${local.resource_prefix}-git-cache"

  lifecycle {
    ignore_changes = all
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "com.buzz.volume"
    value = "git"
  }
}

resource "docker_image" "buzz_relay" {
  name         = "coder-buzz-relay:local"
  keep_locally = true

  build {
    context    = path.module
    dockerfile = "Dockerfile"
    build_args = {
      BUZZ_IMAGE = local.buzz_image
    }
  }
}

resource "docker_image" "postgres" {
  name         = "postgres:17-alpine"
  keep_locally = true
}

resource "docker_image" "redis" {
  name         = "redis:7-alpine"
  keep_locally = true
}

resource "docker_image" "minio" {
  name         = "minio/minio:RELEASE.2025-09-07T16-13-09Z"
  keep_locally = true
}

resource "docker_container" "postgres" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.postgres.image_id
  name     = "${local.resource_prefix}-postgres"
  hostname = "postgres"
  restart  = "unless-stopped"
  memory   = 1024

  env = [
    "POSTGRES_DB=buzz",
    "POSTGRES_USER=buzz",
    "POSTGRES_PASSWORD=${random_password.postgres.result}",
    "PGDATA=/var/lib/postgresql/data/pgdata",
  ]

  volumes {
    container_path = "/var/lib/postgresql/data"
    volume_name    = docker_volume.postgres_data.name
    read_only      = false
  }

  networks_advanced {
    name    = docker_network.buzz.name
    aliases = ["postgres"]
  }

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -U buzz -d buzz"]
    interval     = "5s"
    timeout      = "5s"
    retries      = 12
    start_period = "10s"
  }

  wait         = true
  wait_timeout = 120
}

resource "docker_container" "redis" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.redis.image_id
  name     = "${local.resource_prefix}-redis"
  hostname = "redis"
  restart  = "unless-stopped"
  memory   = 256
  command  = ["redis-server", "--requirepass", random_password.redis.result]

  env = [
    "REDIS_PASSWORD=${random_password.redis.result}",
  ]

  networks_advanced {
    name    = docker_network.buzz.name
    aliases = ["redis"]
  }

  healthcheck {
    test         = ["CMD-SHELL", "redis-cli -a \"$${REDIS_PASSWORD}\" ping | grep -q PONG"]
    interval     = "5s"
    timeout      = "3s"
    retries      = 12
    start_period = "5s"
  }

  wait         = true
  wait_timeout = 60
}

resource "docker_container" "minio" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.minio.image_id
  name     = "${local.resource_prefix}-minio"
  hostname = "minio"
  restart  = "unless-stopped"
  memory   = 512
  command  = ["server", "/data", "--console-address", ":9001"]

  env = [
    "MINIO_ROOT_USER=${random_password.minio_access_key.result}",
    "MINIO_ROOT_PASSWORD=${random_password.minio_secret_key.result}",
  ]

  volumes {
    container_path = "/data"
    volume_name    = docker_volume.minio_data.name
    read_only      = false
  }

  networks_advanced {
    name    = docker_network.buzz.name
    aliases = ["minio"]
  }

  healthcheck {
    test         = ["CMD", "curl", "-f", "http://127.0.0.1:9000/minio/health/live"]
    interval     = "5s"
    timeout      = "5s"
    retries      = 12
    start_period = "10s"
  }

  wait         = true
  wait_timeout = 60
}

resource "docker_container" "workspace" {
  count       = data.coder_workspace.me.start_count
  image       = docker_image.buzz_relay.image_id
  name        = local.resource_prefix
  hostname    = data.coder_workspace.me.name
  working_dir = "/home/coder/repos"

  cpu_shares = data.coder_parameter.cpu.value * 1024
  memory     = data.coder_parameter.memory.value * 1024

  depends_on = [
    docker_container.postgres,
    docker_container.redis,
    docker_container.minio,
  ]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "DOTFILES_URI=${data.coder_parameter.dotfiles_uri.value}",
    "BUZZ_REF=${data.coder_parameter.buzz_ref.value}",

    # Convenience aliases for buzz-relay-start's own dependency checks.
    "POSTGRES_HOST=postgres",
    "POSTGRES_PORT=5432",
    "POSTGRES_USER=buzz",
    "POSTGRES_DB=buzz",
    "POSTGRES_PASSWORD=${random_password.postgres.result}",
    "REDIS_HOST=redis",
    "REDIS_PORT=6379",
    "REDIS_PASSWORD=${random_password.redis.result}",
    "MINIO_HOST=minio",
    "MINIO_PORT=9000",

    # Buzz relay configuration — names and semantics come directly from
    # https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/deploy/compose/compose.yml
    # and .env.example; nothing here is invented.
    "BUZZ_BIND_ADDR=0.0.0.0:3000",
    "BUZZ_HEALTH_PORT=8080",
    "BUZZ_METRICS_PORT=9102",
    "DATABASE_URL=postgres://buzz:${random_password.postgres.result}@postgres:5432/buzz",
    "REDIS_URL=redis://:${random_password.redis.result}@redis:6379",
    "BUZZ_S3_ENDPOINT=http://minio:9000",
    "BUZZ_S3_ADDRESSING_STYLE=path",
    "BUZZ_S3_ACCESS_KEY=${random_password.minio_access_key.result}",
    "BUZZ_S3_SECRET_KEY=${random_password.minio_secret_key.result}",
    "BUZZ_S3_BUCKET=${data.coder_parameter.minio_bucket.value}",
    "BUZZ_GIT_REPO_PATH=/data/git",
    "BUZZ_AUTO_MIGRATE=false",
    "BUZZ_GIT_CONFORMANCE_PROBE=true",
    "RELAY_URL=${data.coder_parameter.relay_public_url.value}",
    "BUZZ_DOMAIN=${local.relay_host}",
    "BUZZ_MEDIA_BASE_URL=${local.media_base_url}",
    "BUZZ_CORS_ORIGINS=${local.cors_origin}",
    "RELAY_OWNER_PUBKEY=${data.coder_parameter.relay_owner_pubkey.value}",
    "BUZZ_REQUIRE_RELAY_MEMBERSHIP=${local.has_owner_pubkey}",
    "RUST_LOG=${data.coder_parameter.rust_log.value}",
  ]

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  volumes {
    container_path = "/data/git"
    volume_name    = docker_volume.git_cache.name
    read_only      = false
  }

  networks_advanced {
    name    = docker_network.buzz.name
    aliases = ["workspace"]
  }

  ports {
    internal = 3000
    external = data.coder_parameter.relay_host_port.value
  }

  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost/", "host.docker.internal")]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id
  daily_cost  = 20

  item {
    key   = "Relay Image"
    value = local.buzz_image
  }
  item {
    key   = "Relay Public URL"
    value = data.coder_parameter.relay_public_url.value
  }
  item {
    key   = "Relay Host Port"
    value = data.coder_parameter.relay_host_port.value
  }
  item {
    key   = "Closed Relay Mode"
    value = local.has_owner_pubkey ? "enabled" : "disabled (no relay_owner_pubkey set)"
  }
  item {
    key   = "CPU Cores"
    value = data.coder_parameter.cpu.value
  }
  item {
    key   = "Memory"
    value = "${data.coder_parameter.memory.value} GB"
  }
}

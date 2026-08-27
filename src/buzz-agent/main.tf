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

data "coder_parameter" "dotfiles_uri" {
  name         = "dotfiles_uri"
  display_name = "Dotfiles URI"
  description  = "Git repository URI containing personal dotfiles. Leave blank to skip."
  type         = "string"
  default      = ""
  mutable      = true
  icon         = "https://raw.githubusercontent.com/coder/coder/main/site/static/icon/terminal.svg"
}

data "coder_parameter" "agent_role" {
  name         = "agent_role"
  display_name = "Agent Role"
  description  = <<-EOT
    Immutable Buzz identity/role for this workspace, e.g. marketing, finance,
    analysis, pm. Each workspace is exactly one Buzz identity — to run
    multiple roles, create one independent workspace per role rather than
    scaling roles within a single workspace. This value (together with this
    workspace's stable Coder owner/workspace identifiers) derives an isolated
    host persistence directory under /data/buzz-agents; it is never used as a
    free-form host path itself, and it cannot be changed after the workspace
    is created (doing so would silently point the workspace at a different
    identity's data).
  EOT
  type         = "string"
  mutable      = false

  validation {
    # Coder supplies an empty sentinel while importing a template to detect
    # persistent resources. agent-data-init rejects it for real workspaces.
    regex = "^$|^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$"
    error = "agent_role must be a lowercase slug of letters, digits, and internal hyphens only (e.g. marketing, finance, analysis, pm)."
  }
}

data "coder_parameter" "buzz_ref" {
  name         = "buzz_ref"
  display_name = "Buzz Commit"
  description  = <<-EOT
    Immutable Buzz commit to run. Selects the public
    ghcr.io/block/buzz-sprig:sha-<7> and ghcr.io/block/buzz:sha-<7> images and
    the Buzz source checkout in ~/repos/buzz.
  EOT
  type         = "string"
  default      = "b622003f74aa5bf9b659786452813299a25e4897"
  mutable      = true

  validation {
    regex = "^[0-9a-fA-F]{7,40}$"
    error = "buzz_ref must be a 7-40 character hex commit SHA."
  }
}

data "coder_parameter" "relay_url" {
  name         = "relay_url"
  display_name = "Relay URL"
  description  = <<-EOT
    The Buzz relay this agent connects to outbound (BUZZ_RELAY_URL), e.g.
    wss://buzz.example.com (matching a buzz-relay workspace's
    relay_public_url) or a local ws://host:port for testing.
  EOT
  type         = "string"
  mutable      = true

  validation {
    # Empty is reserved for Coder's template-import probe. buzz-agent-start
    # requires a relay URL before starting the real agent process.
    regex = "^$|^wss?://[a-zA-Z0-9.-]+(:[0-9]+)?$"
    error = "relay_url must look like wss://buzz.example.com or ws://host:port."
  }
}

data "coder_parameter" "provider" {
  name         = "buzz_agent_provider"
  display_name = "LLM Provider"
  description  = "Which LLM backend buzz-agent uses (BUZZ_AGENT_PROVIDER)."
  type         = "string"
  default      = "anthropic"
  mutable      = true

  option {
    name  = "Anthropic"
    value = "anthropic"
  }
  option {
    name  = "OpenAI-compatible"
    value = "openai"
  }
  option {
    name  = "OpenRouter"
    value = "openrouter"
  }
  option {
    name  = "Databricks"
    value = "databricks"
  }
  option {
    name  = "Databricks (v2)"
    value = "databricks_v2"
  }
}

data "coder_parameter" "model" {
  name         = "buzz_agent_model"
  display_name = "Model"
  description  = <<-EOT
    Model identifier for the selected provider, e.g. claude-sonnet-4-5
    (anthropic), gpt-5 (openai), anthropic/claude-sonnet-4.5 (openrouter), or
    a Databricks served-model name.
  EOT
  type         = "string"
  mutable      = true
}

data "coder_parameter" "endpoint" {
  name         = "buzz_agent_endpoint"
  display_name = "Provider Endpoint"
  description  = <<-EOT
    Required for Databricks (workspace URL, e.g.
    https://dbc-....cloud.databricks.com). Optional base-URL override for
    Anthropic/OpenAI-compatible/OpenRouter — leave blank to use buzz-agent's
    own default for the selected provider.
  EOT
  type         = "string"
  default      = ""
  mutable      = true
}

data "coder_parameter" "respond_to" {
  name         = "buzz_acp_respond_to"
  display_name = "Respond To"
  description  = "Inbound author gate (BUZZ_ACP_RESPOND_TO). Owner control commands (!shutdown/!cancel/!rotate) always bypass this gate."
  type         = "string"
  default      = "owner-only"
  mutable      = true

  option {
    name  = "Owner only"
    value = "owner-only"
  }
  option {
    name  = "Allowlist"
    value = "allowlist"
  }
  option {
    name  = "Anyone"
    value = "anyone"
  }
  option {
    name  = "Nobody (heartbeat only)"
    value = "nobody"
  }
}

data "coder_parameter" "respond_to_allowlist" {
  name         = "buzz_acp_respond_to_allowlist"
  display_name = "Respond To Allowlist"
  description  = "Comma-separated 64-char hex pubkeys. Required when Respond To is Allowlist; the owner is always implicitly included."
  type         = "string"
  default      = ""
  mutable      = true

  validation {
    regex = "^$|^[0-9a-fA-F]{64}(,[0-9a-fA-F]{64})*$"
    error = "must be empty or a comma-separated list of 64-character hex pubkeys."
  }
}

data "coder_parameter" "agents_count" {
  name         = "buzz_acp_agents"
  display_name = "Agent Subprocesses"
  description  = <<-EOT
    Worker concurrency (BUZZ_ACP_AGENTS) for this single workspace's Buzz
    identity/role only — it parallelizes how many turns this one agent_role
    identity can process at once, it does not add more roles or identities.
    To run additional roles (e.g. marketing and finance), create additional
    buzz-agent workspaces, one per role.
  EOT
  type         = "number"
  default      = "1"
  mutable      = true

  validation {
    min = 1
    max = 32
  }
}

data "coder_parameter" "idle_timeout" {
  name         = "buzz_acp_idle_timeout"
  display_name = "Idle Timeout (s)"
  description  = "Max seconds of silence before cancelling a turn (BUZZ_ACP_IDLE_TIMEOUT)."
  type         = "number"
  default      = "620"
  mutable      = true
}

data "coder_parameter" "max_turn_duration" {
  name         = "buzz_acp_max_turn_duration"
  display_name = "Max Turn Duration (s)"
  description  = "Absolute wall-clock cap per turn (BUZZ_ACP_MAX_TURN_DURATION)."
  type         = "number"
  default      = "7200"
  mutable      = true
}

data "coder_parameter" "max_rounds" {
  name         = "buzz_agent_max_rounds"
  display_name = "Max Tool-Loop Rounds"
  description  = "Tool-loop iteration cap; 0 = unlimited (BUZZ_AGENT_MAX_ROUNDS)."
  type         = "number"
  default      = "0"
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
  buzz_sprig_image = "ghcr.io/block/buzz-sprig:sha-${local.buzz_ref_short}"
  resource_prefix  = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"

  # --------------------------------------------------------------------------- #
  # Per-role host bind persistence.
  #
  # /data/buzz-agents is a fixed, non-parameterized host root (a Docker
  # provisioner-host prerequisite documented in README.md) — it is never taken
  # from user input. The per-workspace subpath is built only from this
  # workspace's own stable Coder identifiers (owner name, workspace UUID) and
  # the validated `agent_role` slug, so it can never be redirected to an
  # arbitrary host path, and two workspaces that happen to share a role stay
  # isolated because the workspace UUID is always unique.
  # --------------------------------------------------------------------------- #
  agent_data_host_root      = "/data/buzz-agents"
  agent_data_host_path      = "${local.agent_data_host_root}/${data.coder_workspace_owner.me.name}/${data.coder_parameter.agent_role.value}-${data.coder_workspace.me.id}"
  agent_data_container_root = "/home/coder/agent-data"

  # Maps the generic model/endpoint parameters onto the exact provider-scoped
  # env var names buzz-agent expects (see crates/buzz-agent/README.md at the
  # pinned commit) — never invented, always the literal upstream names.
  provider_env = (
    data.coder_parameter.provider.value == "anthropic" ? {
      ANTHROPIC_MODEL    = data.coder_parameter.model.value
      ANTHROPIC_BASE_URL = data.coder_parameter.endpoint.value
      } : data.coder_parameter.provider.value == "openai" ? {
      OPENAI_COMPAT_MODEL    = data.coder_parameter.model.value
      OPENAI_COMPAT_BASE_URL = data.coder_parameter.endpoint.value
      } : data.coder_parameter.provider.value == "openrouter" ? {
      OPENROUTER_MODEL    = data.coder_parameter.model.value
      OPENROUTER_BASE_URL = data.coder_parameter.endpoint.value
      } : {
      # databricks / databricks_v2
      DATABRICKS_MODEL = data.coder_parameter.model.value
      DATABRICKS_HOST  = data.coder_parameter.endpoint.value
    }
  )
}

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
    script       = "coder stat disk --path /home/coder/agent-data"
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

  # Reports configuration completeness by variable *name* only — never
  # prints a secret value.
  metadata {
    display_name = "Agent Config"
    key          = "agent_config"
    script       = <<-EOT
      #!/bin/bash
      f="$HOME/.config/buzz/agent.env"
      if [ ! -f "$f" ]; then
        printf 'no config file yet'
        exit 0
      fi
      missing=()
      grep -Eq '^BUZZ_PRIVATE_KEY=.+' "$f" || missing+=("BUZZ_PRIVATE_KEY")
      case "$${BUZZ_AGENT_PROVIDER:-}" in
        anthropic) grep -Eq '^ANTHROPIC_API_KEY=.+' "$f" || missing+=("ANTHROPIC_API_KEY") ;;
        openai) grep -Eq '^OPENAI_COMPAT_API_KEY=.+' "$f" || missing+=("OPENAI_COMPAT_API_KEY") ;;
        openrouter) grep -Eq '^OPENROUTER_API_KEY=.+' "$f" || missing+=("OPENROUTER_API_KEY") ;;
      esac
      if [ "$${#missing[@]}" -gt 0 ]; then
        printf 'incomplete: missing %s' "$${missing[*]}"
      else
        printf 'configured'
      fi
    EOT
    interval     = 60
    timeout      = 5
  }

  metadata {
    display_name = "Agent Process"
    key          = "agent_process"
    script       = <<-EOT
      #!/bin/bash
      if pgrep -f 'buzz-acp' >/dev/null 2>&1; then
        echo "running"
      else
        echo "stopped"
      fi
    EOT
    interval     = 30
    timeout      = 5
  }

  # Best-effort outbound TCP reachability to the configured relay — this
  # agent exposes no app/port itself, so there is no local readiness
  # endpoint to poll; this only tells us whether the outbound path is open.
  metadata {
    display_name = "Relay Reachability"
    key          = "relay_reachability"
    script       = <<-EOT
      #!/bin/bash
      url="$${BUZZ_RELAY_URL:-}"
      if [ -z "$url" ]; then
        echo "unknown (BUZZ_RELAY_URL unset)"
        exit 0
      fi
      hostport="$${url#*://}"
      hostport="$${hostport%%/*}"
      host="$${hostport%%:*}"
      port="$${hostport##*:}"
      if [ "$port" = "$host" ]; then
        case "$url" in
          wss://*) port=443 ;;
          *) port=80 ;;
        esac
      fi
      if timeout 3 bash -c "echo >/dev/tcp/$host/$port" 2>/dev/null; then
        echo "reachable ($host:$port)"
      else
        echo "unreachable ($host:$port)"
      fi
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
# Docker resources — no sibling containers, no docker_network, no published
# ports, and no coder_app: this workspace's only network activity is its own
# outbound connection to relay_url.
# --------------------------------------------------------------------------- #

resource "docker_image" "buzz_agent" {
  name         = "coder-buzz-agent:local"
  keep_locally = true

  build {
    context    = path.module
    dockerfile = "Dockerfile"
    build_args = {
      BUZZ_SPRIG_IMAGE = local.buzz_sprig_image
      BUZZ_IMAGE       = local.buzz_image
    }
  }
}

resource "docker_container" "workspace" {
  count       = data.coder_workspace.me.start_count
  image       = docker_image.buzz_agent.image_id
  name        = local.resource_prefix
  hostname    = data.coder_workspace.me.name
  working_dir = "/home/coder/repos"

  cpu_shares = data.coder_parameter.cpu.value * 1024
  memory     = data.coder_parameter.memory.value * 1024

  env = concat(
    [
      "CODER_AGENT_TOKEN=${coder_agent.main.token}",
      "DOTFILES_URI=${data.coder_parameter.dotfiles_uri.value}",
      "BUZZ_REF=${data.coder_parameter.buzz_ref.value}",
      "AGENT_ROLE=${data.coder_parameter.agent_role.value}",
      "AGENT_DATA_ROOT=${local.agent_data_container_root}",
      "AGENT_DATA_HOST_PATH=${local.agent_data_host_path}",
      "BUZZ_RELAY_URL=${data.coder_parameter.relay_url.value}",
      "BUZZ_AGENT_PROVIDER=${data.coder_parameter.provider.value}",
      "BUZZ_ACP_RESPOND_TO=${data.coder_parameter.respond_to.value}",
      "BUZZ_ACP_RESPOND_TO_ALLOWLIST=${data.coder_parameter.respond_to_allowlist.value}",
      "BUZZ_ACP_AGENTS=${data.coder_parameter.agents_count.value}",
      "BUZZ_ACP_IDLE_TIMEOUT=${data.coder_parameter.idle_timeout.value}",
      "BUZZ_ACP_MAX_TURN_DURATION=${data.coder_parameter.max_turn_duration.value}",
      "BUZZ_AGENT_MAX_ROUNDS=${data.coder_parameter.max_rounds.value}",
    ],
    [for k, v in local.provider_env : "${k}=${v}" if v != ""]
  )

  # Bind-mounts this workspace's dedicated, collision-safe host directory
  # (see local.agent_data_host_path) into a data root distinct from
  # /home/coder itself, so image-provided home-directory files (.bashrc,
  # etc.) are never hidden by the mount. startup.sh symlinks the conventional
  # ~/repos, ~/.config/buzz, and ~/.local/state/buzz-agent paths into
  # subdirectories of this mount. Docker reattaches the same host_path on
  # every container recreation (stop/start, template upgrade) because it is
  # derived only from this workspace's stable owner/workspace-id/agent_role
  # values, never from ephemeral container state.
  volumes {
    container_path = local.agent_data_container_root
    host_path      = local.agent_data_host_path
    read_only      = false
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
  daily_cost  = 10

  item {
    key   = "Sprig Image"
    value = local.buzz_sprig_image
  }
  item {
    key   = "Agent Role"
    value = data.coder_parameter.agent_role.value
  }
  item {
    key   = "Persistent Data Path (host)"
    value = local.agent_data_host_path
  }
  item {
    key   = "Persistent Data Path (container)"
    value = local.agent_data_container_root
  }
  item {
    key   = "LLM Provider"
    value = data.coder_parameter.provider.value
  }
  item {
    key   = "Relay URL"
    value = data.coder_parameter.relay_url.value
  }
  item {
    key   = "Respond To"
    value = data.coder_parameter.respond_to.value
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

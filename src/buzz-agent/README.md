# buzz-agent

A Coder workspace template that runs a single [Buzz](https://github.com/block/buzz)
ACP agent identity (`buzz-acp` + `buzz-agent`, from the Sprig multicall
binary) connected outbound to a Buzz relay. Unlike `buzz-relay`, this
workspace has **no sibling containers, no published port, and no
`coder_app`** — it is a persistent interactive development environment whose
only network activity is its own outbound WebSocket connection to the relay
you configure.

Each workspace is exactly **one Buzz identity/role** — set by the required,
immutable `agent_role` parameter (e.g. `marketing`, `finance`, `analysis`,
`pm`) — with its own persistent host directory under `/data/buzz-agents`
(see "Persistence and lifecycle"). To run multiple role agents, create one
`buzz-agent` workspace per role (see "One workspace per role").

Buzz is pinned to a single immutable upstream commit
(`b622003f74aa5bf9b659786452813299a25e4897`) by default. The Sprig multicall
binary (`buzz-acp`, `buzz-agent`, `buzz-dev-mcp`, `rg`, `tree`, `buzz`,
`git-credential-nostr`, `git-sign-nostr`) comes from the public, multi-arch
`ghcr.io/block/buzz-sprig:sha-b622003` image built by upstream's own CI for
that exact commit — this template runs those prebuilt binaries rather than
recompiling Sprig's Rust workspace at image-build time (see "Why prebuilt
binaries" below). The same source commit is checked out into `~/repos/buzz`
for reading and reference.

## What runs here

```
  buzz-agent workspace (this template)
  ┌───────────────────────────────────────────────────┐
  │  buzz-agent-start                                  │
  │    → checks ~/.config/buzz/agent.env (0600)        │
  │    → configures URL-scoped git credentials         │
  │    → exec buzz-acp  ──── outbound WSS ────────────►│──► your buzz-relay
  │         └─ spawns buzz-agent (the LLM loop) and     │    (a separate
  │            buzz-dev-mcp as ACP/MCP subprocesses     │     workspace, or
  └───────────────────────────────────────────────────┘     any Buzz relay)
```

`buzz-acp` listens for @mentions/DMs on the relay (subject to the "Respond
To" gate below), spawns `buzz-agent` over stdio using the Agent Client
Protocol, and `buzz-agent` calls your chosen LLM provider and executes tool
calls via MCP. No inbound port is ever opened by this workspace.

## Why prebuilt binaries

The task allows building Sprig from source unless verified public prebuilt
usage is more reliable. Before choosing the prebuilt path we verified,
directly against the pinned commit:

- `ghcr.io/block/buzz-sprig:sha-b622003` is publicly pullable, multi-arch
  (amd64 + arm64), and its `org.opencontainers.image.revision` OCI
  annotation matches the pinned commit exactly.
- The `sprig` binary is a statically-linked musl executable that runs
  unmodified on this template's glibc-based `ghcr.io/coder/code-server`
  base image.
- It contains exactly the multicall tool set this task requires: `buzz-acp`,
  `buzz-agent`, `buzz-dev-mcp`, `rg`, `tree`, `buzz`, `git-credential-nostr`,
  `git-sign-nostr`.

Given that, copying the prebuilt binaries keeps this template's build fast
and byte-for-byte identical to what upstream's own CI publishes. The Buzz
source is still checked out into `~/repos/buzz` for reading, and nothing
prevents manually running `cargo build --release --profile sprig -p sprig`
from that checkout if you need a modified build.

## Parameters

| Parameter                       | Default            | Notes                                                                 |
| -------------------------------- | -------------------- | ----------------------------------------------------------------------- |
| `agent_role`                     | *(required)*         | Immutable lowercase slug identifying this workspace's Buzz identity/role, e.g. `marketing`, `finance`, `analysis`, `pm`. Derives this workspace's isolated persistent data directory (see "Persistence and lifecycle"). Cannot be changed after workspace creation. |
| `cpu`                            | `2`                  |                                                                          |
| `memory`                         | `4` (GB)             |                                                                          |
| `dotfiles_uri`                   | *(empty)*            | Optional personal dotfiles repo.                                       |
| `buzz_ref`                       | `b622003f74aa5bf9b659786452813299a25e4897` | Immutable Buzz commit; selects the Sprig/relay images and `~/repos/buzz` checkout. |
| `relay_url`                      | *(required)*         | `wss://` or `ws://` URL of the relay this agent connects to (`BUZZ_RELAY_URL`). |
| `buzz_agent_provider`            | `anthropic`          | `anthropic`, `openai`, `openrouter`, `databricks`, or `databricks_v2` (`BUZZ_AGENT_PROVIDER`). |
| `buzz_agent_model`               | *(required)*         | Model id for the selected provider.                                     |
| `buzz_agent_endpoint`            | *(empty)*            | Required for Databricks (workspace host URL); optional base-URL override otherwise. |
| `buzz_acp_respond_to`            | `owner-only`         | Inbound author gate (`BUZZ_ACP_RESPOND_TO`).                            |
| `buzz_acp_respond_to_allowlist`  | *(empty)*            | Comma-separated hex pubkeys; required when `buzz_acp_respond_to` is `allowlist`. |
| `buzz_acp_agents`                | `1`                  | Worker concurrency **for this single `agent_role` identity only** (`BUZZ_ACP_AGENTS`) — see "One workspace per role" below. |
| `buzz_acp_idle_timeout`          | `620`                | Seconds of silence before cancelling a turn.                            |
| `buzz_acp_max_turn_duration`     | `7200`               | Absolute wall-clock cap per turn.                                       |
| `buzz_agent_max_rounds`          | `0`                  | Tool-loop iteration cap; `0` = unlimited.                                |

Non-secret settings above (relay URL, provider name, model, endpoint,
respond-to policy, timeouts) are ordinary container environment variables set
by Terraform. **No secret ever passes through a `coder_parameter`.**

## One workspace per role

This template runs exactly **one Buzz identity/role per workspace**. To run
several role agents (e.g. `marketing`, `finance`, `analysis`, `pm`), create
one independent `buzz-agent` workspace per role, each with its own
`agent_role` value:

```console
coder create marketing-agent --template buzz-agent --parameter agent_role=marketing
coder create finance-agent   --template buzz-agent --parameter agent_role=finance
coder create analysis-agent  --template buzz-agent --parameter agent_role=analysis
coder create pm-agent        --template buzz-agent --parameter agent_role=pm
```

`buzz_acp_agents` (`BUZZ_ACP_AGENTS`) is **not** a way to run multiple roles
from one workspace — it only controls how many turns *this one identity* can
process concurrently. Increase it if a single role needs more throughput;
add another workspace (with a different `agent_role`) to add another role.

## Identity and secrets

This workspace will not start `buzz-acp` until
`~/.config/buzz/agent.env` (mode `0600`, on this workspace's persistent
per-role host directory — see "Persistence and lifecycle") contains
`BUZZ_PRIVATE_KEY` and the credential(s) required by the selected provider:

| Provider          | Required secret(s) in `agent.env`        |
| ------------------ | ------------------------------------------ |
| `anthropic`        | `ANTHROPIC_API_KEY`                        |
| `openai`           | `OPENAI_COMPAT_API_KEY`                    |
| `openrouter`       | `OPENROUTER_API_KEY`                       |
| `databricks(_v2)`  | *(none required — `DATABRICKS_TOKEN` optional; omit it to use browser OAuth)* |

On first start, `buzz-agent-start` generates a fresh Nostr identity (via
`buzz-admin generate-key`) and writes it, together with a commented template
for the provider credential(s), into `~/.config/buzz/agent.env`. It then
exits without starting `buzz-acp` and logs exactly which secret(s) are still
missing (by name only — never by value) to
`~/agent-data/logs/buzz-agent/agent.log`.

**To finish setup:**

1. Open a terminal in the workspace and check the public key that was
   printed: `grep '^# Agent public key' ~/.config/buzz/agent.env`.
2. Give that public key to the owner of the target relay so they can run
   `buzz-admin add-member --pubkey <that key> --role member` from the relay
   workspace. The Relay template's wrapper loads its protected admin
   environment automatically. Skip this if the relay is running in open mode,
   i.e. no `relay_owner_pubkey` was set on it.
3. Edit `~/.config/buzz/agent.env` and fill in the provider credential(s)
   from the table above.
4. Run `buzz-agent-start` from a terminal (or restart the workspace) to
   start the agent.

Nothing in this template ever prints `BUZZ_PRIVATE_KEY` or any provider
credential to a log, and none of this file's contents are ever written to
Terraform state.

## Persistence and lifecycle

Each `buzz-agent` workspace bind-mounts a **dedicated host directory** —
rather than a Docker-managed named volume — so that identity, config,
repositories, and logs for that one role survive container recreation and
are trivially locatable on the Docker provisioner host:

```text
Host:      /data/buzz-agents/<owner>/<agent_role>-<workspace-id>
             (e.g. /data/buzz-agents/alice/marketing-8f14e45f-fceb-4f3e-8a1a-2fcb1f5f6b2f)
             │
             ▼  bind mount
Container: /home/coder/agent-data/
             ├── repos/               ← ~/repos              (working trees, incl. ~/repos/buzz)
             ├── config/buzz/         ← ~/.config/buzz        (mode 700; agent.env identity+credentials)
             ├── state/buzz-agent/    ← ~/.local/state/buzz-agent
             └── logs/buzz-agent/     (buzz-agent-start / buzz-acp startup log)
```

The resolved host path and the container data root are both published,
non-secret, as this workspace's `coder_metadata` ("Persistent Data Path
(host)" / "(container)") and as the `AGENT_DATA_HOST_PATH` /
`AGENT_DATA_ROOT` container environment variables.

**Why a per-role host directory and not `/home/coder` as a named volume:**

- **Multiple role agents.** This template is designed to run many role
  identities (`marketing`, `finance`, `analysis`, `pm`, ...), each as its own
  workspace. A host bind mount rooted at `/data/buzz-agents` gives every
  role's data a stable, inspectable, backup-able path on the provisioner
  host, rather than an opaque Docker volume name per workspace.
- **Collision safety.** The host path is derived only from this workspace's
  *stable Coder identifiers* — the owner's username and the workspace's UUID
  — plus the validated `agent_role` slug: `/data/buzz-agents/<owner>/<agent_role>-<workspace-id>`.
  `/data/buzz-agents` itself is a fixed constant in `main.tf`, never a
  user-supplied parameter, so no workspace can be pointed at an arbitrary
  host path. Two workspaces that pick the same `agent_role` (even under the
  same owner) never collide, because the workspace UUID is always unique.
- **`/home/coder` stays image-owned.** The bind mount targets
  `/home/coder/agent-data`, not `/home/coder` itself, so it never hides
  image-provided home-directory files (`.bashrc`, etc.). `startup.sh`
  idempotently symlinks `~/repos`, `~/.config/buzz`, and
  `~/.local/state/buzz-agent` into it on every start.

| Data                                                             | Storage                              | Survives `coder stop`/`start` | Survives template update | Survives workspace deletion |
| ------------------------------------------------------------------| --------------------------------------- | :----------------------------: | :------------------------: | :---------------------------: |
| Identity/provider config (`~/.config/buzz/agent.env`)             | host bind mount (`.../agent-data/config/buzz`) | ✅ | ✅ | ✅ (host directory is untouched) |
| Repositories/working trees (`~/repos`, incl. `~/repos/buzz`)      | host bind mount (`.../agent-data/repos`)       | ✅ | ✅ | ✅ |
| Agent state (`~/.local/state/buzz-agent`)                         | host bind mount (`.../agent-data/state/buzz-agent`) | ✅ | ✅ | ✅ |
| Startup/agent logs                                                | host bind mount (`.../agent-data/logs/buzz-agent`) | ✅ | ✅ | ✅ |
| Everything else under `/home/coder` (shell history, caches, etc.) | container filesystem (image layer)   | ❌ | ❌ | ❌ |

`coder stop` stops the workspace container (the `buzz-acp` process stops with
it). `coder start` (and a template upgrade) recreates the container and
reattaches the **same** `host_path` — deterministically re-derived from this
workspace's unchanging owner/workspace-id/`agent_role` — so
`buzz-agent-start` reuses the existing identity/config instead of
regenerating anything.

> **Deleting this workspace does NOT delete its host directory.** Unlike a
> Docker named volume (which Coder can garbage-collect with the workspace),
> a bind-mounted host directory is ordinary host filesystem state that
> Terraform never manages the lifecycle of. Cleaning up
> `/data/buzz-agents/<owner>/<agent_role>-<workspace-id>` after deleting a
> workspace is an **explicit host-admin operation** — for example:
>
> ```console
> # On the Docker provisioner host, after confirming the workspace is deleted
> # and its data is no longer needed:
> sudo rm -rf /data/buzz-agents/alice/marketing-8f14e45f-fceb-4f3e-8a1a-2fcb1f5f6b2f
> ```
>
> This is the flip side of the durability guarantee: nothing you didn't ask
> for gets deleted, but nothing gets cleaned up for you either.

### Host prerequisites

The Docker provisioner host must have `/data/buzz-agents` available as
**durable storage** before creating any `buzz-agent` workspace:

- It must exist, be writable by the Docker daemon's user (normally `root`),
  and be backed by storage that survives host reboots (not `tmpfs` or a
  container-ephemeral path) — e.g. a local disk/RAID/LVM volume or a network
  filesystem mounted at boot.
- It needs enough capacity for **all role workspaces combined**: each role's
  directory holds a Buzz source checkout (`~/repos/buzz`, tens of MB),
  whatever repositories the agent works in day to day, and small
  config/state/log files. Size it like you would any developer home
  directory, multiplied by the number of roles you plan to run
  concurrently.
- Back it up like any other stateful host directory (e.g. periodic
  `rsync`/snapshot of `/data/buzz-agents`) — Coder and Terraform have no
  knowledge of, or responsibility for, this path's durability.
- Per-agent directories look like:
  `/data/buzz-agents/alice/marketing-8f14e45f-fceb-4f3e-8a1a-2fcb1f5f6b2f`,
  `/data/buzz-agents/alice/finance-1b7e6c9a-9e3d-4a2b-8b0e-6f9c2d1a7e44`,
  `/data/buzz-agents/bob/analysis-3c2f9e11-...` — one directory per
  workspace, grouped by owner.
- This template creates neither `/data/buzz-agents` nor its per-owner
  subdirectory; only the final per-workspace leaf directory is created (by
  Docker, as part of the bind mount) and then had its ownership fixed by
  `startup.sh`. `startup.sh` never touches `/data/buzz-agents` itself or any
  other workspace's directory under it.

## Owner control commands

Once running, the relay owner can always reach this agent regardless of the
"Respond To" setting by DMing/mentioning it with:

- `!shutdown` — gracefully exits `buzz-acp`.
- `!cancel` — cancels the current in-flight turn in that channel.
- `!rotate` — starts a fresh ACP session on the next event in that channel.

## Security notes

- No Docker socket is mounted into this workspace.
- No port is published and no `coder_app` is defined — this template's only
  network path is the outbound connection `buzz-acp` makes to `relay_url`.
- Provider API keys are never passed to MCP tool subprocesses: upstream's
  `buzz-agent` only forwards a fixed, minimal environment
  (`PATH`, `HOME`, `TERM`, `LANG`, `LC_ALL`, `TMPDIR`) to spawned MCP
  servers, so a compromised tool cannot read your LLM credentials from its
  own environment.
- Commits made under this agent's identity are signed with its Nostr key via
  `git-sign-nostr` (`git config --system` sets `gpg.format x509`, matching
  upstream's own Sprig image configuration) — this is a code-signing
  identity, separate from the relay-auth identity in `BUZZ_PRIVATE_KEY`
  only in purpose, not in key material (both use the same agent keypair).
- `agent-data-init` only ever `chown`s this workspace's own bind-mounted
  directory (`AGENT_DATA_ROOT`, i.e. the per-role leaf under
  `/data/buzz-agents`) — never `/data/buzz-agents` itself or any sibling
  role's directory — and only uses the base image's passwordless `sudo` for
  that one, narrowly-scoped `chown -R`. `~/.config/buzz` is kept at mode
  `0700` for the identity/credential file it holds.
- Neither `BUZZ_PRIVATE_KEY` nor any provider credential is ever read by
  Terraform, so none of it can appear in Terraform state, plan output, or
  `coder_metadata`; only non-secret paths (`AGENT_DATA_HOST_PATH`,
  `AGENT_DATA_ROOT`) are exposed that way.

## Validating this template

```console
# Format and validate the Terraform (requires network access to download providers)
terraform fmt -check
terraform init -backend=false
terraform validate

# Lint the shell scripts
shellcheck startup.sh buzz-agent-start agent-data-init

# Build the workspace image (requires network access to ghcr.io)
docker build \
  --build-arg BUZZ_SPRIG_IMAGE=ghcr.io/block/buzz-sprig:sha-b622003 \
  --build-arg BUZZ_IMAGE=ghcr.io/block/buzz:sha-b622003 \
  -t buzz-agent:test .
```

After deploying, from inside the workspace:

```console
cat "$AGENT_DATA_ROOT/logs/buzz-agent/agent.log"   # setup guidance / start log
pgrep -af buzz-acp                                 # confirm the harness is running
```

### Docker/runtime mount test: persistence and non-root writability

This exercises the exact mechanism `main.tf`/`startup.sh` rely on — a host
directory that does not exist yet (so Docker auto-creates it, typically
owned by `root`), `agent-data-init` verifying writability and fixing ownership
when required, and a second, freshly recreated container reattached to the same
host directory — without needing a real Coder deployment:

```console
IMG=buzz-agent:test   # built above

HOST_PARENT="$(mktemp -d)"
HOST_DIR="$HOST_PARENT/agent-data"   # deliberately does not exist yet

# --- "workspace" container #1: first start ---
# --entrypoint bash overrides the image's code-server entrypoint so this
# runs as a plain shell, the way a one-off validation container should.
docker run --rm --entrypoint bash -v "$HOST_DIR:/home/coder/agent-data" "$IMG" -c '
  set -euo pipefail
  /usr/local/bin/agent-data-init
  echo repo-canary   > "$HOME/repos/CANARY"
  echo config-canary > "$HOME/.config/buzz/CANARY"
  echo log-canary    > /home/coder/agent-data/logs/buzz-agent/CANARY
  stat -c "in-container agent-data: %U:%G %a" /home/coder/agent-data
'

# The HOST directory itself (not just the container view of it) is now
# owned by the image's non-root coder uid/gid, not root — on a native Linux
# Docker host. (On Docker Desktop for macOS/Windows the bind-mount
# file-sharing layer virtualizes ownership, so this specific host-side check
# is only meaningful run against a native Linux Docker daemon; the
# in-container checks above and below hold on any host.)
stat -c "on host: %u:%g %a" "$HOST_DIR"

# --- "workspace" container #2: simulates stop/start or a template upgrade
#     recreating the container against the SAME host directory ---
docker run --rm --entrypoint bash -v "$HOST_DIR:/home/coder/agent-data" "$IMG" -c '
  set -euo pipefail
  /usr/local/bin/agent-data-init
  test "$(cat "$HOME/repos/CANARY")" = repo-canary
  test "$(cat "$HOME/.config/buzz/CANARY")" = config-canary
  test "$(cat /home/coder/agent-data/logs/buzz-agent/CANARY)" = log-canary
  test -w "$HOME/repos" && test -w "$HOME/.config/buzz"
  stat -Lc "%a" "$HOME/.config/buzz" | grep -qx 700
  echo "PERSISTENCE OK: config/repo/log canaries survived recreation and remain non-root-writable"
'

rm -rf "$HOST_PARENT"
```

Expected output: the first block prints `in-container agent-data: coder:coder
755` (or your image's non-root user/group); `stat` on the host shows the
matching non-zero uid/gid instead of `0:0`; the second block prints
`PERSISTENCE OK: ...`. This was run manually against this change to confirm
the behavior (see PR description / validation notes) — it is not wired into
CI because it requires a Docker daemon.

## Known limitations

- This template does not automate relay membership enrollment (`buzz-admin
  add-member`) for the agent's freshly generated identity — that requires
  the relay owner's signing key and is a manual, documented step above.
- Private channels have no REST/event membership API upstream as of the
  pinned commit; use the Buzz CLI's `create_channel` (the creator becomes a
  member automatically) as documented in `crates/buzz-acp/README.md`.
- Host directory cleanup after workspace deletion is a manual, out-of-band
  host-admin step (see "Persistence and lifecycle") — this template
  intentionally never deletes anything under `/data/buzz-agents`.
- `/data/buzz-agents` durability, capacity, and backups are a host
  prerequisite this template assumes rather than provisions; a Docker
  provisioner host without durable storage at that path silently loses this
  data on host failure exactly like any other host bind mount would.
- The "Relay Reachability" metadata item is a best-effort plain TCP check
  against the host/port parsed from `relay_url` — it confirms only that the
  network path is open, not that the relay's WebSocket handshake or Buzz's
  own NIP-42 auth would succeed.

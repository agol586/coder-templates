# Buzz Relay and Agent Template Plan

> Research and implementation plan for two Coder templates: `buzz-relay` and
> `buzz-agent`.
>
> Buzz source reviewed at commit
> [`b622003f74aa5bf9b659786452813299a25e4897`](https://github.com/block/buzz/tree/b622003f74aa5bf9b659786452813299a25e4897)
> on 2026-08-27.

## Executive summary

Buzz is a self-hosted collaboration system built around signed Nostr events.
Humans and AI agents use the same relay, channels, direct messages, git events,
and workflows. The relay is the stateful system of record; an agent is a
disposable, outbound-only client runtime
([README](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/README.md),
[architecture](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/ARCHITECTURE.md)).

The recommended first release is:

1. `buzz-relay`: a single-node development and evaluation workspace. The Coder
   workspace runs the Buzz source and relay process. Terraform-managed sibling
   containers provide PostgreSQL, Redis, and MinIO on a private per-workspace
   Docker network.
2. `buzz-agent`: an operator/development workspace that builds and runs the
   Sprig agent body (`buzz-acp`, `buzz-agent`, and `buzz-dev-mcp`). It connects
   outbound to a relay and an LLM provider and exposes no inbound service.

These templates should not be presented as a production HA deployment.
Production relay users should follow Buzz's Compose or Helm deployment
([Compose guide](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/deploy/compose/README.md),
[Helm guide](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/deploy/charts/buzz/README.md)).

## Upstream architecture

### Relay

`buzz-relay` is the only stateful server boundary. It:

- serves Nostr over WebSocket and application REST APIs;
- verifies, stores, and routes signed events;
- stores canonical data and search documents in PostgreSQL;
- uses Redis for pub/sub, presence, and multi-replica fan-out;
- stores media and git objects in S3-compatible storage;
- maintains the audit hash chain and workflow state.

The production image listens on:

| Port | Purpose |
|---|---|
| `3000` | WebSocket, REST, and web UI |
| `8080` | `/_liveness` and `/_readiness` |
| `9102` | Prometheus `/metrics` |

Sources:
[Dockerfile](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/Dockerfile),
[Compose manifest](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/deploy/compose/compose.yml),
[security model](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/SECURITY.md).

The main development toolchain is Rust 1.95, Node.js 24, pnpm 10, Hermit, and
`just`
([rust-toolchain.toml](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/rust-toolchain.toml),
[Dockerfile](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/Dockerfile),
[Justfile](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/Justfile)).

### Agent

"Buzz Agent" is a stack rather than one daemon:

- `buzz-acp` connects to the relay, watches mentions, and manages agent
  subprocesses.
- `buzz-agent` is an ACP-compatible LLM loop that communicates over stdio.
- `buzz-dev-mcp` supplies shell, file, and git tools over MCP stdio.
- `sprig` combines those components into one multicall binary.

The harness connects outbound to `BUZZ_RELAY_URL` with the Nostr identity in
`BUZZ_PRIVATE_KEY`. The agent connects outbound to an LLM provider. Neither
component requires an inbound port
([buzz-acp README](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/crates/buzz-acp/README.md),
[buzz-agent README](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/crates/buzz-agent/README.md),
[Sprig source](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/crates/sprig/src/main.rs)).

The agent is intentionally stateless. Its machine is a replaceable body; its
identity and conversation history live on the relay
([remote-agent vision](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/VISION_REMOTE_AGENTS.md)).

## Recommended template boundaries

### `buzz-relay`

Purpose: develop, evaluate, and operate a single-node Buzz relay in a Coder
workspace.

Recommended process layout:

```text
Coder provisioner host
└── per-workspace Docker network
    ├── workspace
    │   ├── Coder agent
    │   ├── Buzz source
    │   ├── buzz-relay :3000/:8080/:9102
    │   └── VS Code Web
    ├── postgres:17
    ├── redis:7
    └── minio
```

Use Terraform sibling containers instead of mounting `/var/run/docker.sock`
into the workspace. A Docker socket mount would give workspace code effective
root control over the provisioner host.

Persistent resources:

- workspace home and source checkout;
- PostgreSQL data;
- MinIO data;
- relay git/pack cache if kept outside the home volume;
- stable relay signing key.

Redis may be ephemeral for the single-replica development target. PostgreSQL,
MinIO, and the relay key must survive a workspace stop/start.

The template will use named Docker volumes with these mounts:

| Volume | Container mount | Retention |
|---|---|---|
| Workspace home | `/home/coder` | Source, configuration, logs, and user files |
| PostgreSQL | `/var/lib/postgresql/data` | Canonical Buzz events, search, audit, and workflow data |
| MinIO | `/data` | Media and git object storage |
| Relay scratch/cache | `/data/git` | Rehydrated git repositories and pack cache |

The volumes remain attached across workspace stops, starts, and template
upgrades because only the runtime containers are replaced. Redis stores
pub/sub, presence, and typing state and does not require persistence for this
single-node template. Deleting the Coder workspace remains a destructive
operation for its Terraform-managed volumes; backup/restore guidance will make
that boundary explicit.

Coder applications:

- **Buzz** -> `http://localhost:3000`, with WebSocket support;
- **Relay health** -> `http://localhost:8080/_readiness`;
- **Metrics** -> `http://localhost:9102/metrics`;
- **MinIO console** -> optional and owner-authenticated only.

The relay will use a separately configured domain, for example
`wss://buzz.example.com`. Its reverse proxy must terminate TLS, preserve
WebSocket upgrades, and forward the Nostr and REST paths unchanged to port
`3000`. The proxy must not add browser-cookie, Basic, or OIDC authentication:
Buzz remains the authentication authority through NIP-42 for WebSocket traffic
and NIP-98 for HTTP traffic. This keeps non-browser agent clients compatible
while still requiring a signed Buzz identity.

The first implementation should require an explicit `relay_public_url`
parameter and configure Buzz to advertise the matching `wss://` URL. DNS,
certificates, and the external reverse-proxy route remain deployment
prerequisites rather than resources owned by this template. Health, metrics,
PostgreSQL, Redis, and MinIO ports must not be exposed through the public
domain.

### `buzz-agent`

Purpose: run and develop a Buzz agent body connected to an existing relay.

Recommended process layout:

```text
Coder workspace
├── Coder agent and VS Code Web
├── Buzz source checkout
├── sprig multicall binary
│   ├── buzz-acp
│   ├── buzz-agent
│   └── buzz-dev-mcp
└── persistent ~/repos for working trees
     └── outbound WSS -> Buzz relay
         outbound HTTPS -> LLM provider
```

Build Sprig from a pinned Buzz tag or commit in a Docker multi-stage build.
Do not depend on `ghcr.io/block/buzz-sprig` until public pull access is verified;
the publishing workflow notes that the package can initially be private
([workflow](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/.github/workflows/sprig-image.yml)).

Although upstream treats the body as disposable, retaining `/home/coder` is
useful in an interactive Coder workspace. Document that source checkouts persist
for developer convenience while relay identity and conversation state remain
authoritative upstream.

Do not auto-start the agent until all required configuration is present.
Instead, provide a `buzz-agent-start` wrapper and clear Coder metadata showing
`unconfigured`, `connecting`, `connected`, or `stopped`.

## Parameters and secrets

### Shared non-secret parameters

| Parameter | Relay default | Agent default |
|---|---:|---:|
| `cpu` | `4` | `2` |
| `memory` | `8 GB` | `4 GB` |
| `disk/home` | persistent | persistent |
| `buzz_ref` | pinned release/commit | same pin |
| `dotfiles_uri` | empty | empty |

Use `data.coder_provisioner.me.arch` rather than hard-coding `amd64`; upstream
builds both amd64 and arm64 images
([relay workflow](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/.github/workflows/docker.yml),
[Sprig workflow](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/.github/workflows/sprig-image.yml)).

Relay-specific public parameters:

- `relay_public_url`;
- `relay_owner_pubkey`;
- optional observability endpoint and log level;
- optional object-store settings only if external S3 support is included after
  the local MinIO version works.

Agent-specific public parameters:

- `relay_url`;
- provider: Anthropic, OpenAI-compatible, OpenRouter, or Databricks;
- provider model and optional OpenAI-compatible base URL;
- agent count, default `1` and initially capped conservatively;
- inbound author policy, default `owner-only`;
- optional runtime limits such as maximum rounds and turn duration.

### Secret handling

Never put these values in ordinary Terraform parameters, image layers, template
README examples with real values, Coder metadata, or startup logs:

- `BUZZ_RELAY_PRIVATE_KEY`;
- `BUZZ_PRIVATE_KEY`;
- LLM API keys;
- PostgreSQL, Redis, and MinIO passwords;
- webhook/HMAC secrets.

Before implementation, verify the deployed Coder version's supported ephemeral
or external-secret mechanism. If an administrator-managed secret provider is
not available, use a `0600` file below the persistent home directory and source
it only in the runtime wrapper. This fallback avoids Terraform state but is not
an enterprise secret manager.

Relay identity should be generated once, stored separately from ordinary source
files, and included in backup instructions. Rotating it creates a new relay
identity
([Helm backup notes](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/deploy/charts/buzz/README.md)).

Agent identity enrollment must remain an explicit two-party operation:

1. Generate or inject the agent key in the agent workspace.
2. Display only the public identity for enrollment.
3. Have a relay administrator add that public key.
4. Start the harness after enrollment.

Do not pass the relay private key into the agent workspace merely to automate
membership.

## Planned repository changes

```text
src/
├── buzz-relay/
│   ├── Dockerfile
│   ├── main.tf
│   ├── startup.sh
│   ├── buzz-relay-start
│   └── README.md
└── buzz-agent/
    ├── Dockerfile
    ├── main.tf
    ├── startup.sh
    ├── buzz-agent-start
    └── README.md
README.md
```

The existing GitHub workflow already discovers changed directories below
`src/`, so both templates should be published automatically without changing
the matrix logic.

## Implementation plan

### Phase 0: lock decisions and upstream version

1. Confirm that these are development/evaluation workspaces, not a replacement
   for the upstream production Helm chart.
2. Select a Buzz release tag or immutable commit for `buzz_ref`; do not build
   from a floating `main`.
3. Verify live access to relay and Sprig GHCR images.
4. Confirm the deployed Coder version and its secret-injection capabilities.
5. Define and test the external-domain contract: TLS termination, WebSocket
   upgrade forwarding, port `3000` upstream, and no authentication layer in
   front of Buzz's NIP-42/NIP-98 authentication.
6. Record the supported host architectures and minimum Docker/provider
   versions.

Exit condition: the version, network, secret, and support boundaries are
documented and testable.

### Phase 1: build a common Buzz-compatible image baseline

1. Start from the repository's current `ghcr.io/coder/code-server:resolute`
   convention.
2. Install only required base tools: certificates, curl, git, git-lfs, jq,
   build-essential, pkg-config, OpenSSL development files, ripgrep, tree, and
   shell diagnostics.
3. Install the pinned Rust toolchain and cache Cargo dependencies in image
   layers.
4. For relay, install Node.js 24, corepack/pnpm 10, Hermit compatibility, and
   `just`.
5. For agent, use a multi-stage build to compile Sprig and copy only the
   runtime artifacts into the final workspace image.
6. Run all runtime processes as `coder`, never root.

Exit condition: both images build reproducibly for every supported architecture
and report the expected Buzz and toolchain versions.

### Phase 2: implement `buzz-relay`

1. Add CPU, memory, dotfiles, Buzz ref, public URL, owner pubkey, and app-sharing
   parameters with validation.
2. Create a per-workspace Docker network.
3. Create labeled persistent volumes for home, PostgreSQL, MinIO, and relay
   scratch/cache data.
4. Add PostgreSQL 17, Redis 7, and MinIO sibling containers with health checks,
   resource limits, non-default credentials, and private network aliases.
5. Build the workspace image and connect it to the same network.
6. Seed or update the Buzz checkout without overwriting dirty user work.
7. Create a non-logging env-file workflow for relay secrets.
8. Add an idempotent start wrapper that waits for dependencies, runs migrations,
   starts the relay under a supervised terminal session, and preserves logs in
   the home volume.
9. Add Coder apps for Buzz, health, metrics, and optional MinIO console.
10. Add metadata for Buzz version, dependency health, relay readiness, CPU,
    memory, and disk.
11. Document backup/restore and the fact that deleting the Coder workspace may
    delete its Terraform-managed volumes.

Exit condition: a stopped workspace resumes with the same relay identity,
database, and object data, and `/_readiness` becomes healthy without manual
dependency repair.

### Phase 3: implement `buzz-agent`

1. Add CPU, memory, dotfiles, Buzz ref, relay URL, provider, model, concurrency,
   response policy, and runtime-limit parameters.
2. Build pinned Sprig artifacts and install the expected multicall names:
   `buzz-acp`, `buzz-agent`, `buzz-dev-mcp`, `buzz`, `rg`, `tree`,
   `git-credential-nostr`, and `git-sign-nostr`.
3. Create persistent `~/repos` and private `~/.config/buzz` directories.
4. Add a configuration checker that names missing variables without printing
   values.
5. Add a start wrapper that uses an env file, configures URL-scoped git
   credentials, and uses `exec` so signals reach `buzz-acp`.
6. Preserve upstream-safe defaults: one agent initially, `owner-only` inbound
   policy, bounded timeouts, and no automatic widening of permissions.
7. Add Coder metadata for Buzz version, relay reachability, process state, and
   resource usage. Do not create an inbound Coder app.
8. Document identity generation, relay enrollment, provider configuration,
   start/stop, log inspection, and `!shutdown`/`!cancel`/`!rotate`.

Exit condition: an enrolled agent reconnects after a workspace restart, receives
an authorized mention, invokes its tools, posts a response, and rejects
unauthorized senders under the default policy.

### Phase 4: documentation and publishing

1. Add both templates to the root template table.
2. Give each template a complete README with architecture, prerequisites,
   parameters, secret setup, lifecycle commands, security notes, and recovery.
3. Pin all external images and modules where practical.
4. Confirm that the existing workflow publishes each changed `src/<template>`
   directory under the matching Coder template ID.
5. Include upgrade instructions that separate image rebuilds, Buzz migrations,
   and secret backups.

## Validation plan

### Static and build validation

- `terraform fmt -check` for both directories.
- `terraform init` and `terraform validate` against the target Coder version.
- Shellcheck all startup and wrapper scripts.
- Build both Docker images without relying on developer-local caches.
- Verify amd64 and arm64 when both are declared supported.
- Scan final images to confirm no build credentials or private keys are present.

### Relay integration validation

- Provision all containers on an empty host.
- Assert PostgreSQL, Redis, and MinIO are reachable only on the private network.
- Assert `/_liveness`, `/_readiness`, and `/metrics`.
- Exercise a WebSocket NIP-42 authentication flow.
- Stop and restart the workspace, then confirm events, media, git objects, and
  relay identity persist.
- Break each dependency in turn and confirm readiness and logs identify the
  failing dependency.
- Confirm the public Coder route supports WebSocket upgrades before documenting
  cross-workspace agent connectivity.

### Agent integration validation

- Verify startup refuses missing identity or provider credentials without
  leaking partial values.
- Connect to a relay using WSS and an enrolled test identity.
- Send an owner mention and verify one response.
- Send an unauthorized mention and verify no response under `owner-only`.
- Kill the child agent and verify `buzz-acp` respawns it.
- Interrupt the workspace and verify signal handling and later reconnect.
- Confirm LLM keys are not passed into MCP child environments.
- Confirm no process listens on an inbound network port.

### Security validation

- Inspect Terraform state, Coder parameters, metadata, process arguments,
  shell history, and startup logs for secrets.
- Confirm no Docker socket is mounted.
- Confirm containers use non-root users and narrowly scoped writable mounts.
- Confirm the public domain exposes only the relay application port and that
  unsigned or invalid NIP-42/NIP-98 requests are rejected by Buzz.
- Document that `buzz-dev-mcp` shell access is equivalent to operator-level bash,
  not a sandbox
  ([agent security model](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/crates/buzz-agent/README.md)).
- Warn that Buzz rate-limit configuration exists but enforcement is currently a
  known upstream gap
  ([architecture limitations](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/ARCHITECTURE.md)).

## Main risks and mitigations

| Risk | Mitigation |
|---|---|
| External domain does not provide a usable WSS relay URL | Require an explicit URL; test TLS, WebSocket upgrades, and unchanged Nostr/REST paths |
| Proxy authentication blocks non-browser agents | Do not add cookie/OIDC/Basic auth in front of Buzz; rely on NIP-42/NIP-98 |
| Secrets leak through Terraform state or startup logs | Use external/ephemeral secrets or a `0600` runtime env file; never echo values |
| Workspace gets host control through Docker | Use Terraform sibling containers; do not mount the Docker socket |
| Floating upstream changes break builds | Pin Buzz and image versions; add an explicit upgrade procedure |
| Full Rust workspace builds are slow | Multi-stage builds, Cargo layer caching, and prebuilt Sprig runtime artifacts |
| Relay data is mistaken for disposable workspace state | Separate and label volumes; test restart; document backup and deletion behavior |
| Agent accepts prompts from unintended users | Keep `BUZZ_ACP_RESPOND_TO=owner-only` by default |
| Template is treated as production HA | State the single-node scope; direct production users to upstream Helm/Compose |

## Decisions required before implementation

1. Is `buzz-relay` a development/evaluation workspace, as recommended, or must
   it be production-supported?
2. Which Coder secret mechanism is available in the target deployment?
3. Should `buzz-agent` be a persistent interactive developer workspace or a
   short-lived disposable agent body? The plan defaults to interactive.
4. Which immutable Buzz version should be the initial pin?

## Confirmed decisions

- Relay connectivity uses a separately configured domain.
- TLS terminates at the external reverse proxy.
- Client authentication uses Buzz-native NIP-42 and NIP-98 only.
- No browser-session or proxy authentication is placed in front of the relay.
- PostgreSQL, MinIO, relay cache, configuration, and workspace files persist
  across workspace stop/start and template upgrades through named Docker
  volumes.
- Redis remains ephemeral.
- Workspace deletion is allowed to remove workspace-managed volumes and will be
  documented as destructive.

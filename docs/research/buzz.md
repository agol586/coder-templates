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
- `buzz-relay`: PostgreSQL, MinIO, relay cache, configuration, and workspace
  files persist across workspace stop/start and template upgrades through
  named Docker volumes.
- `buzz-agent`: identity/provider config, repositories/working trees, logs,
  and agent state persist across workspace stop/start and template upgrades
  through a **host bind mount** (not a named Docker volume) rooted at
  `/data/buzz-agents`, one dedicated directory per workspace — see the
  "buzz-agent: per-role host bind persistence" addendum below. This is a
  deliberate divergence from `buzz-relay`'s named-volume approach, driven by
  the requirement to run multiple independent role identities
  (`marketing`, `finance`, `analysis`, `pm`, ...) each as its own workspace
  with an operator-inspectable, backup-able host path.
- Redis remains ephemeral.
- Workspace deletion is allowed to remove workspace-managed **named Docker
  volumes** (`buzz-relay`) and will be documented as destructive. It does
  **not** remove `buzz-agent`'s bind-mounted host directory — that cleanup is
  an explicit, separate host-admin operation (see the addendum below).

## Implementation addendum

Refinements discovered while implementing `src/buzz-relay` and
`src/buzz-agent` against the pinned commit. These are corrections/additions
to the plan above, not changes to the confirmed decisions.

- **pnpm version**: `package.json` at the pinned commit pins
  `packageManager: pnpm@11.4.0`, not pnpm 10 as estimated above. The relay
  template's optional Node toolchain (for manual rebuilds) installs pnpm via
  `corepack enable`, which reads this field directly, so no hardcoded pnpm
  version was needed in the Dockerfile.
- **Prebuilt images over from-source builds, for both templates**: both
  `buzz-relay` and `buzz-agent` copy binaries from the pinned, verified-public
  `ghcr.io/block/buzz:sha-b622003` and `ghcr.io/block/buzz-sprig:sha-b622003`
  images (multi-arch; `org.opencontainers.image.revision` confirmed to match
  the pinned commit) via multi-stage `COPY --from=`, rather than compiling the
  Rust workspace at image-build time. This was verified directly (pulling and
  running both images, confirming the Sprig multicall binary is a static musl
  executable that runs unmodified on the glibc `code-server` base) before
  choosing it over a from-source build. `buzz-relay`'s image still installs an
  optional Rust/Node/`just` toolchain and checks out Buzz source into
  `~/repos/buzz` at startup, so a manual from-source rebuild remains possible;
  `buzz-agent`'s image omits that toolchain entirely to stay minimal, since it
  has no from-source rebuild requirement.
- **MinIO bucket bootstrap folded into the relay startup wrapper**: rather
  than a separate Terraform-managed one-shot `minio-init` container (as
  upstream's own Compose bundle uses), `buzz-relay-start` runs the equivalent
  `mc mb --ignore-existing` / `mc anonymous set none` idempotently on every
  start. Terraform's `kreuzwerker/docker` provider has no first-class
  "wait for a one-shot container to exit 0" primitive, so folding this into
  the already-idempotent startup wrapper (which already waits for MinIO to be
  healthy) was more reliable than adding a fourth sibling container.
- **Database migrations**: `BUZZ_AUTO_MIGRATE` is left `false`; `buzz-relay-start`
  runs `buzz-admin migrate` explicitly and logs it, so schema changes are
  always visible in the startup log instead of happening silently inside the
  relay process.
- **Infrastructure secret generation**: PostgreSQL/Redis/MinIO credentials are
  generated via Terraform's `random_password` (alphanumeric only, to avoid
  URL-percent-encoding in `DATABASE_URL`/`REDIS_URL`), marked sensitive, and
  injected only as container environment variables. Buzz's own signing
  identity (`BUZZ_RELAY_PRIVATE_KEY`, `BUZZ_GIT_HOOK_HMAC_SECRET` for the
  relay; `BUZZ_PRIVATE_KEY` and LLM provider credentials for the agent) is
  generated at container startup via `buzz-admin generate-key` /
  `openssl rand -hex 32` and persisted only in a `0600` file under the home
  volume — never in Terraform state, never logged.

- **`buzz-agent`: per-role host bind persistence (follow-up requirement)**:
  the original `buzz-agent` implementation persisted `/home/coder` (identity,
  `~/repos/buzz`, `~/.config/buzz`) through a Docker named volume, deleted
  along with the workspace — matching `buzz-relay`'s pattern. A follow-up
  requirement introduced running **multiple role agents** (`marketing`,
  `finance`, `analysis`, `pm`, ...), one independent Coder workspace per
  role, with persistence rooted in **host bind storage** at
  `/data/buzz-agents` rather than opaque per-workspace named volumes. This
  changes only `buzz-agent`; `buzz-relay` is unaffected and keeps its named
  volumes.
  - A new immutable, required `agent_role` parameter (validated as a
    lowercase slug: `^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$`) identifies the
    workspace's one Buzz identity. `BUZZ_ACP_AGENTS` is unchanged in meaning
    — it remains worker concurrency for that single identity, not a way to
    run multiple roles from one workspace — and its parameter description
    was reworded to say so explicitly.
  - The host path is derived, never taken as free-form input:
    `/data/buzz-agents/<owner>/<agent_role>-<workspace-id>`, using
    `data.coder_workspace_owner.me.name` and `data.coder_workspace.me.id`
    (both stable, Coder-assigned) plus the validated role slug.
    `/data/buzz-agents` itself is a Terraform-local constant. The workspace
    UUID suffix keeps two workspaces that pick the same role isolated.
  - `docker_container.workspace`'s `volumes` block uses `host_path` (a bind
    mount) instead of `volume_name`, targeting `/home/coder/agent-data` — a
    dedicated data root, not `/home/coder` itself, so the bind mount never
    hides image-provided home-directory files. The prior
    `docker_volume.home_volume` resource was removed.
  - A new standalone script, `agent-data-init`, runs on every container
    start (from `startup.sh`, and independently for testing): it fixes
    ownership of *only* `AGENT_DATA_ROOT` (never the shared
    `/data/buzz-agents` parent) via the base `code-server` image's
    passwordless `sudo` when Docker has auto-created the bind source as
    root, fails loudly if it cannot be made writable, lays out
    `repos/`, `config/buzz/` (mode `0700`), `state/buzz-agent/`, and
    `logs/buzz-agent/` under it, and idempotently symlinks
    `~/repos`, `~/.config/buzz`, and `~/.local/state/buzz-agent` into those
    subdirectories.
  - Verified directly: built the image, then ran it twice with `docker run
    --entrypoint bash -v <nonexistent-host-dir>:/home/coder/agent-data`
    against the same host directory — the first run showed Docker
    auto-creating the bind source as root and `agent-data-init` fixing
    ownership and writing config/repo/log canary files; the second run
    (simulating container recreation) confirmed those canaries persisted and
    the directories remained non-root-writable without any further chown.
    Also verified the loud-failure path: a pre-existing non-empty real
    directory at a symlink target correctly aborts with a clear error
    instead of silently overwriting data.
  - Documented as a host-admin prerequisite, not something this template
    provisions: `/data/buzz-agents` must be durable, adequately sized
    storage reachable by the Docker provisioner; deleting a workspace does
    not delete its bind-mounted directory, so cleanup and backups are
    explicit, separate host-admin operations (see `buzz-agent/README.md`
    "Persistence and lifecycle" and "Host prerequisites").

## Buzz Desktop onboarding and hosted communities

Reviewed at the pinned Buzz commit
[`b622003f74aa5bf9b659786452813299a25e4897`](https://github.com/block/buzz/tree/b622003f74aa5bf9b659786452813299a25e4897),
whose Desktop package version is `0.5.20`.

- **Hosted communities** is Block's optional Relay hosting product. Its
  settings page explicitly states that Buzz works with any Relay and that
  Builderlab sign-in is used only to create and manage communities hosted by
  Block
  ([source](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/desktop/src/features/settings/ui/HostedCommunitiesSettingsCard.tsx)).
  A Builderlab account is not required for a self-hosted Relay.
- To connect the public Desktop build to a self-hosted Relay during onboarding,
  choose **I already have a community** → **I'm a member or admin**, then enter
  the Relay in **Community URL or invite link**. After onboarding, use the
  community switcher → **Add a community** → **Join an existing community**
  ([welcome flow](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/desktop/src/features/communities/ui/WelcomeSetup.tsx),
  [join form](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/desktop/src/features/onboarding/ui/InviteRedeemForm.tsx),
  [add-community flow](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/desktop/src/features/communities/ui/AddCommunityDialog.tsx)).
- The join form accepts `wss://buzz.agol66.uk`, `https://buzz.agol66.uk`, or
  the bare hostname and normalizes them to the WebSocket Relay URL
  ([source](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/desktop/src/features/communities/relayProbe.ts)).
- Desktop still creates a local Nostr identity and profile. That keypair is the
  user's Buzz identity, not a Builderlab account. On a closed Relay, its public
  key must be admitted by the Relay owner. When membership is denied, Desktop
  displays the local `npub` for copying
  ([source](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/desktop/src/features/onboarding/ui/MembershipDenied.tsx));
  it is also available under Profile settings
  ([source](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/desktop/src/features/settings/ui/ProfileSettingsCard.tsx)).
- `BUZZ_RELAY_URL` can provide a startup default, but a community URL selected
  in the UI has higher precedence
  ([source](https://github.com/block/buzz/blob/b622003f74aa5bf9b659786452813299a25e4897/desktop/src-tauri/src/relay.rs)).

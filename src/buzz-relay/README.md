# buzz-relay

A Coder workspace template that runs [Buzz](https://github.com/block/buzz) — a
Nostr-based relay for AI coding agents — together with the PostgreSQL, Redis,
and MinIO services it depends on. The relay binary, PostgreSQL, Redis, and
MinIO all run as Terraform-managed Docker containers on a private
per-workspace Docker network; only the relay's app port is ever published to
the host.

Buzz is pinned to a single immutable upstream commit
(`b622003f74aa5bf9b659786452813299a25e4897`) by default. The relay and
`buzz-admin` binaries come from the public, multi-arch
`ghcr.io/block/buzz:sha-b622003` image built by upstream's own CI for that
exact commit (verified against the image's
`org.opencontainers.image.revision` annotation); the same source commit is
also checked out into `~/repos/buzz` for reading, rebuilding, or contributing
upstream.

## Architecture

```
                         (prerequisite, not managed by this template)
   Nostr/Buzz clients ────────────────► External reverse proxy
                                          (owns the public domain,
                                           terminates TLS, forwards
                                           WebSocket/HTTP unchanged)
                                                   │
                                                   │ plain HTTP/WS
                                                   ▼
                                     host:<relay_host_port> ──► workspace container:3000
                                                                        │
                                     ┌──────────────────────────────────┼───────────────────────┐
                                     │         private per-workspace Docker network              │
                                     │                                                            │
                                     │  postgres:17-alpine   redis:7-alpine   minio (S3 API)      │
                                     │  (named volume)        (no volume)     (named volume)      │
                                     └────────────────────────────────────────────────────────────┘

   Coder browser (owner only) ──► coder_app "buzz"/"readiness"/"metrics" ──► agent-local ports
                                   (3000 / 8080 / 9102 — separate from the public domain above)
```

- **buzz-relay** (`buzz-relay`, `buzz-admin`): the workspace container. Runs
  code-server (via the `vscode-web` registry module), the Buzz relay process,
  and a startup wrapper that waits for dependencies, bootstraps MinIO,
  migrates the database, and supervises the relay.
- **postgres**, **redis**, **minio**: Terraform-managed sibling containers on
  a dedicated `docker_network`, started/stopped in lockstep with the
  workspace via `count = data.coder_workspace.me.start_count`. They are never
  bound to a host port and never get a `coder_app` — only the workspace
  container (and, through it, the relay) is reachable from outside the
  network.

## Prerequisites

This template does **not** create or manage DNS, TLS certificates, or a
reverse proxy — that is intentional; see "Confirmed decisions" in
`docs/research/buzz.md`. Before pointing real Nostr clients at this relay,
you (or your platform team) must run an external reverse proxy that:

1. Owns a domain (e.g. `buzz.example.com`) with a valid TLS certificate.
2. Terminates TLS and forwards **WebSocket and HTTP traffic unchanged** to
   `<coder-host>:<relay_host_port>` (default host port `3000`) — no path
   rewriting, no added headers required.
3. Performs **no additional authentication**. Buzz authenticates client
   connections itself via Nostr NIP-42 (relay auth) and NIP-98 (HTTP auth).
   Adding cookie, Basic, or OIDC auth in front of the public relay would
   break legitimate Nostr clients and is explicitly out of scope for this
   template.

Set the `relay_public_url` parameter (e.g. `wss://buzz.example.com`) to
exactly the URL your reverse proxy serves; the relay advertises this value
back to clients as `RELAY_URL` and derives its media base URL and CORS
origin from the same host.

## Parameters

| Parameter            | Default                                    | Notes                                                                                     |
| --------------------- | ------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `cpu`                 | `4`                                          | Workspace container only; siblings use fixed modest limits (Postgres 1 GB, Redis 256 MB, MinIO 512 MB). |
| `memory`              | `8` (GB)                                     | Workspace container only.                                                                  |
| `dotfiles_uri`        | *(empty)*                                    | Optional personal dotfiles repo.                                                            |
| `buzz_ref`            | `b622003f74aa5bf9b659786452813299a25e4897`   | Immutable Buzz commit. Selects the `ghcr.io/block/buzz:sha-<7 chars>` image and the `~/repos/buzz` checkout. |
| `relay_public_url`    | *(required)*                                 | `wss://` URL served by your external reverse proxy, e.g. `wss://buzz.example.com`.          |
| `relay_owner_pubkey`  | *(empty)*                                    | Optional 64-char hex Nostr pubkey. When set, enables closed-relay membership mode.           |
| `minio_bucket`        | `buzz-media`                                 | S3 bucket used for Buzz media and git objects.                                              |
| `relay_host_port`     | `3000`                                       | Host port your reverse proxy should target. Immutable after creation.                       |
| `rust_log`            | `buzz_relay=info,buzz_db=info,buzz_auth=info,buzz_pubsub=info,tower_http=info` | Passed through as `RUST_LOG`.                                        |

## Identity and secrets

- **Infrastructure credentials** (PostgreSQL, Redis, MinIO) are generated by
  Terraform's `random_password` resource, marked sensitive, and injected only
  as container environment variables — they are never surfaced as a
  `coder_parameter`, `coder_metadata` item, or in startup logs.
- **The relay's own Nostr signing identity** (`BUZZ_RELAY_PRIVATE_KEY`) and
  its git-hook HMAC secret (`BUZZ_GIT_HOOK_HMAC_SECRET`) are *not* generated
  by Terraform and never touch Terraform state. On first boot,
  `buzz-relay-start` generates them once via `buzz-admin generate-key` /
  `openssl rand -hex 32` and writes them to
  `~/.config/buzz-relay/relay.env` with `0600` permissions on the persistent
  home volume. Subsequent starts reuse this file unchanged. **Back this file
  up** — losing it changes the relay's identity from clients' perspective.
  Nothing in this template ever prints its contents to logs.
- **The Relay admin environment** is refreshed at
  `~/.config/buzz-relay/admin.env` with `0600` permissions on every start. It
  contains the runtime PostgreSQL/Redis URLs and relay signing key required by
  `buzz-admin`. The installed `buzz-admin` wrapper loads this file
  automatically, preventing the source checkout's localhost-oriented `.env`
  from overriding the private Docker network addresses. Protect this file like
  the relay identity file.

## Persistence and lifecycle

| Data                              | Storage                                    | Survives `coder stop`/`start` | Survives template update | Survives workspace deletion |
| ---------------------------------- | -------------------------------------------- | :----------------------------: | :------------------------: | :---------------------------: |
| `/home/coder` (relay identity, dotfiles, `~/repos/buzz` checkout) | named volume `..-home`         | ✅ | ✅ | ❌ (deleted with the volume) |
| PostgreSQL data                   | named volume `..-postgres-data`             | ✅ | ✅ | ❌ |
| MinIO objects                     | named volume `..-minio-data`                | ✅ | ✅ | ❌ |
| `/data/git` (relay git cache/config) | named volume `..-git-cache`               | ✅ | ✅ | ❌ |
| Redis data                        | *(no volume — intentionally ephemeral)*     | ❌ | ❌ | ❌ |

> **Deleting this workspace deletes its named Docker volumes**, including
> the PostgreSQL database, MinIO objects, and the relay's signing identity.
> There is no separate backup mechanism in this template — snapshot the
> volumes yourself (`docker run --rm -v <volume>:/from -v $PWD:/to alpine cp -a /from/. /to/`)
> before deleting a workspace you care about.

`coder stop` removes the workspace and sibling containers (all gated by
`count = data.coder_workspace.me.start_count`) but leaves every named volume
in place; `coder start` recreates the containers and reattaches the same
volumes, then `buzz-relay-start` reuses the existing relay identity and
database rather than regenerating anything.

## Enrolling the relay owner and agents

1. Start the workspace and open the **Relay Readiness** and **Relay Metrics**
   owner-only apps to confirm the relay is healthy.
2. If you set `relay_owner_pubkey`, the relay runs in closed membership mode;
   add additional members from a relay workspace terminal:

   ```bash
   buzz-admin add-member --pubkey <hex-or-npub> --role member
   buzz-admin list-members
   ```

   The installed wrapper loads the protected Relay admin environment
   automatically; do not source the Buzz source checkout's development
   `.env`, which points at localhost.
3. Point `buzz-agent` workspaces (see the sibling `buzz-agent` template) or
   any Nostr/Buzz client at `relay_public_url`.

## Security notes

- No Docker socket is mounted into this workspace.
- PostgreSQL, Redis, and MinIO are reachable only from the private
  per-workspace Docker network — never bound to a host port, never exposed
  as a `coder_app`.
- The three owner-only `coder_app`s (`buzz`, `readiness`, `metrics`) proxy
  through the Coder agent and are authenticated by Coder itself; they are a
  separate, internal access path from the public domain described above and
  must not be confused with it.
- Buzz's own upstream `ARCHITECTURE.md` documents a known gap: granular
  per-client rate limiting is not yet implemented as of the pinned commit.
  Treat this relay as suitable for development/evaluation, not
  production-scale public exposure, until upstream closes that gap.
- `BUZZ_AUTO_MIGRATE` is deliberately left `false`; migrations only ever run
  from the explicit, logged `buzz-admin migrate` step in
  `buzz-relay-start`, so a schema change is always visible in the log
  instead of happening silently inside the relay process.

## Validating this template

```console
# Format and validate the Terraform (requires network access to download providers)
terraform fmt -check
terraform init -backend=false
terraform validate

# Lint the shell scripts
shellcheck startup.sh buzz-relay-start

# Build the workspace image (requires network access to ghcr.io)
docker build --build-arg BUZZ_IMAGE=ghcr.io/block/buzz:sha-b622003 -t buzz-relay:test .
```

After deploying, verify the full dependency chain from inside the workspace:

```console
curl -sf http://localhost:8080/_readiness   # relay readiness
curl -sf http://localhost:9102/metrics | head  # Prometheus metrics
pg_isready -h postgres -U buzz -d buzz
redis-cli -h redis -a "$REDIS_PASSWORD" --no-auth-warning ping
curl -sf http://minio:9000/minio/health/live
```

## Known limitations

- Redis has no persistent volume by design (see confirmed decisions in
  `docs/research/buzz.md`); a `coder stop`/`start` cycle or container
  restart clears Redis-backed ephemeral state (e.g. pub/sub fan-out,
  transient caches). This does not affect durable relay data, which lives
  in PostgreSQL and MinIO.
- `relay_host_port` is immutable after workspace creation (changing it would
  silently break an already-configured reverse proxy); create a new
  workspace if you need a different host port.
- This template does not manage MinIO's console (port 9001); use `mc` from
  inside the workspace, or add your own tooling, if you need bucket
  browsing beyond bootstrap.

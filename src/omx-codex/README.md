# OMX Codex Workspace

A batteries-included [Coder](https://coder.com) template for Codex and oh-my-codex development on Ubuntu 26.04.

## Features

| Feature | Details |
|---------|---------|
| **Base image** | [`ghcr.io/coder/code-server:resolute`](https://github.com/coder/code-server/pkgs/container/code-server) |
| **Workspace** | Persistent projects directory at `~/repos` |
| **IDE** | VS Code Web (code-server) |
| **Languages** | Current Node.js LTS through nvm, latest stable Go, and Python 3 |
| **AI tools** | [OpenAI Codex](https://github.com/openai/codex) and [oh-my-codex](https://github.com/Yeachan-Heo/oh-my-codex) |
| **Code intelligence** | [CodeGraph](https://github.com/colbymchenry/codegraph), connected globally to Codex |
| **Skills** | All [mattpocock/skills](https://github.com/mattpocock/skills), installed globally for Codex |
| **Spec-driven development** | [GitHub Spec Kit](https://github.com/github/spec-kit) `specify` CLI |
| **CLI tools** | Git, Git LFS, ripgrep, fd, fzf, jq, tmux, shellcheck, SQLite, build-essential, and more |
| **Dotfiles** | Optional personal dotfiles repository |
| **Resources** | Configurable CPU, memory, and npm registry |

Tool releases intentionally follow their latest or LTS channels when the image is rebuilt.

## Prerequisites

- A running [Coder](https://coder.com/docs/install) deployment
- Docker on the Coder provisioner host

## Quick Start

```bash
git clone https://github.com/agol586/coder-templates.git
cd coder-templates
coder templates create omx-codex --directory src/omx-codex
coder create my-codex-workspace --template omx-codex
coder ssh my-codex-workspace
```

Authenticate Codex after entering the workspace:

```bash
codex login
```

The shell and VS Code Web open in `~/repos`.

## Per-project Setup

Clone or create projects under `~/repos`. CodeGraph and Spec Kit only modify a repository when explicitly initialized:

```bash
cd ~/repos/my-project

# Build the local semantic code graph used by the Codex MCP integration.
codegraph init

# Initialize Spec Kit in the current repository using Codex skills.
specify init --here --integration codex --integration-options="--skills"
```

The mattpocock skills are installed automatically. Some skills have optional interactive configuration; run `/setup-matt-pocock-skills` inside Codex when needed.

## Template Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `cpu` | Number of CPU cores (2–16) | `2` |
| `memory` | RAM in GB (4–32) | `4` |
| `npm_registry` | npm registry URL | `https://registry.npmjs.org` |
| `dotfiles_uri` | Git repository containing personal dotfiles | *(empty)* |

## Installed Commands

```bash
node --version
go version
codex --version
omx --version
codegraph --version
uv --version
specify version
```

Run `omx doctor` to inspect the oh-my-codex setup and `codegraph status` from an initialized project to inspect its index.

## Security Notes

- The template does not collect or persist an OpenAI API key in Terraform state.
- Codex, nvm, uv, and CodeGraph are installed from their official upstream installation endpoints.
- OMX advanced modes can relax Codex approval or sandbox behavior. Use them only with trusted repositories.
- CodeGraph indexing is local to each project and is not started automatically.
- CodeGraph telemetry is disabled in the workspace image with `CODEGRAPH_TELEMETRY=0`.

## Architecture

```text
Coder deployment
└── Docker workspace
    ├── /home/coder                    persistent volume
    │   ├── repos/                     default working directory
    │   ├── .agents/skills/            global mattpocock skills
    │   ├── .codex/                    Codex and OMX configuration
    │   ├── .codegraph/                CodeGraph bundle
    │   └── .omx/                      OMX state
    └── code-server                    VS Code Web
```

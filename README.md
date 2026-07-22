# coder-templates

A collection of [Coder](https://coder.com) workspace templates for enterprise development environments.

## Templates

| Template | Description |
|----------|-------------|
| [enterprise-golang](./src/enterprise-golang) | Go (Golang) development workspace with VS Code Web, gopls, golangci-lint, Delve debugger, and configurable GOPROXY |
| [enterprise-node](./src/enterprise-node) | Node.js development workspace with VS Code Web, TypeScript language server, ESLint, Prettier, and configurable npm registry |
| [enterprise-base](./src/enterprise-base) | General-purpose enterprise workspace with VS Code Web and a persistent home directory |
| [claude-code](./src/claude-code) | Claude Code AI agent workspace with code-server, Go toolchain, MCP servers, and preset demo app |
| [omx-codex](./src/omx-codex) | Ubuntu 26.04 Codex workspace with oh-my-codex, CodeGraph, Spec Kit, Node.js, Go, and global Codex skills |

## Getting Started

1. Install the Coder CLI:

   ```bash
   # Linux / macOS
   curl -L https://coder.com/install.sh | sh
   ```

2. Log in to your Coder deployment:

   ```bash
   coder login https://<your-coder-url>
   ```

3. Create a template:

   ```bash
   coder templates create enterprise-golang --directory src/enterprise-golang
   ```

4. Create a workspace:

   ```bash
   coder create my-workspace --template enterprise-golang
   ```

See each template's `README.md` for full details.

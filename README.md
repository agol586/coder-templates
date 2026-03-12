# coder-templates

A collection of [Coder](https://coder.com) workspace templates for enterprise development environments.

## Templates

| Template | Description |
|----------|-------------|
| [enterprise-golang](./enterprise-golang) | Production-ready Go (Golang) development workspace with VS Code Web, gopls, golangci-lint, Delve debugger, and enterprise module proxy support |

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
   coder templates create enterprise-golang --directory enterprise-golang
   ```

4. Create a workspace:

   ```bash
   coder create my-workspace --template enterprise-golang
   ```

See each template's `README.md` for full details.

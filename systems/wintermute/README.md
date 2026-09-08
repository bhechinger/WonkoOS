# Wintermute

Wintermute is the Apple Silicon macOS laptop. Nix is installed independently;
the `homeConfigurations.wintermute` Home Manager profile manages Codex, its
GitHub MCP helper, Node.js, OmniGraph, Kitty and its terminfo, the OmniGraph
context skill, and Codex's OmniGraph allow rule.

Codex owns `~/.codex/config.toml` and `~/.codex/auth.json`. Home Manager must
not replace them because they contain machine-specific project paths, plugin
state, and authentication.

From this repository on Deepthought, build or deploy the profile directly in
Wintermute's Nix store with:

```sh
make build-wintermute
make deploy-wintermute
```

The deploy target activates the exact generation returned by the build target;
Wintermute does not need a repository checkout.

Point the `command` in Codex's existing `[mcp_servers.github]` configuration at
the managed helper once per config reset, preserving every other setting:

```toml
[mcp_servers.github]
command = "codex-github-mcp"
```

Verify the setup with:

```sh
codex --version
codex login status
gh auth status
infocmp -x xterm-kitty
omnigraph query recent_context --graph nix --params '{"project":"nix:wonkoos:"}' --json
```

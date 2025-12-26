# Changelog

All notable changes to the Elixir LSP plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-12-26

### Added

- Initial release of Elixir LSP plugin for Claude Code
- ElixirLS language server integration
- Support for `.ex`, `.exs`, and `.heex` file extensions
- Real-time diagnostics for compilation errors and warnings
- Code navigation features (go to definition, find references)
- Hover information for types and documentation
- Workspace symbol search
- Dialyzer integration enabled by default
- Auto-restart on crash with max 5 restart attempts
- 15-second startup timeout for large projects
- Optimized settings for Phoenix and Ecto projects
- Comprehensive README with installation and troubleshooting guide

### Configuration

- `dialyzerEnabled: true` - Type checking via Dialyzer
- `mixEnv: "dev"` - Development environment by default
- `dialyzerFormat: "dialyxir_long"` - Detailed Dialyzer output
- `fetchDeps: false` - Manual dependency management
- `suggestSpecs: false` - No automatic @spec suggestions
- `enableTestLenses: false` - Disabled for performance

[1.0.0]: https://github.com/14hippos/sparkflow/tree/main/elixir-lsp-plugin

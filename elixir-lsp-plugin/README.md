# Elixir LSP Plugin for Claude Code

ElixirLS language server integration for real-time Elixir code intelligence in Claude Code.

## Features

Once installed, Claude Code will provide:

- **Real-time diagnostics** - Compilation errors and warnings as you type
- **Go to definition** - Jump to module and function definitions
- **Find references** - Locate all usages of functions and modules
- **Hover information** - Type information and inline documentation
- **Workspace symbols** - Search for functions, modules, and types across your project
- **Code completion** - Context-aware suggestions (when supported by ElixirLS)

## Prerequisites

**IMPORTANT**: You must install the ElixirLS language server binary separately. This plugin configures how Claude Code connects to ElixirLS, but does not include the binary itself.

### Installing ElixirLS

#### Option 1: Download Prebuilt Release (Recommended)

1. Download the latest release from GitHub:
   ```bash
   cd ~/bin  # or any directory in your PATH
   curl -fLO https://github.com/elixir-lsp/elixir-ls/releases/latest/download/elixir-ls.zip
   unzip elixir-ls.zip -d elixir-ls
   chmod +x elixir-ls/language_server.sh
   ```

2. Create a wrapper script named `elixir-ls` in your PATH:
   ```bash
   cat > ~/bin/elixir-ls << 'EOF'
   #!/bin/bash
   exec ~/bin/elixir-ls/language_server.sh "$@"
   EOF
   chmod +x ~/bin/elixir-ls
   ```

3. Ensure `~/bin` is in your PATH:
   ```bash
   # Add to your ~/.bashrc, ~/.zshrc, or equivalent:
   export PATH="$HOME/bin:$PATH"

   # Reload your shell or source the file:
   source ~/.zshrc  # or ~/.bashrc
   ```

#### Option 2: Build from Source

```bash
git clone https://github.com/elixir-lsp/elixir-ls.git
cd elixir-ls
mix deps.get
MIX_ENV=prod mix compile
MIX_ENV=prod mix elixir_ls.release2

# The binary will be in release/language_server.sh
# Create a wrapper script in your PATH
cat > ~/bin/elixir-ls << EOF
#!/bin/bash
exec $(pwd)/release/language_server.sh "\$@"
EOF
chmod +x ~/bin/elixir-ls
```

#### Verify Installation

```bash
which elixir-ls
# Should output: /Users/Tadd/.mix/escripts/elixir-ls (or similar)
```

If `which elixir-ls` returns nothing, ElixirLS is not installed or not in your PATH.

## Installation

### For SparkFlow Project (Team-Scoped)

This plugin is included in the SparkFlow repository. To enable it:

```bash
cd /Users/Tadd/src/14hippos/sparkflow
claude plugin install ./elixir-lsp-plugin --scope project
```

Verify the plugin is installed:

```bash
claude plugin list
# or within Claude Code:
/plugin
```

### For Other Projects (User-Scoped)

To use this plugin globally for all your Elixir projects:

```bash
claude plugin install /Users/Tadd/src/14hippos/sparkflow/elixir-lsp-plugin --scope user
```

## Configuration

The LSP server is configured via `.lsp.json` with the following settings:

### File Extensions

- `.ex` - Elixir source files
- `.exs` - Elixir script files
- `.heex` - Phoenix HEEx template files

### ElixirLS Settings

**Dialyzer Integration**: Enabled by default for type checking
- `dialyzerEnabled: true` - Runs Dialyzer analysis
- `dialyzerFormat: "dialyxir_long"` - Uses Dialyxir-style formatting
- `dialyzerWarnOpts: []` - Default warning options

**Environment**:
- `mixEnv: "dev"` - Runs in development mode
- `MIX_ENV: "dev"` - Environment variable set for ElixirLS process

**Auto-Restart**:
- `restartOnCrash: true` - Automatically restarts if ElixirLS crashes
- `maxRestarts: 5` - Maximum restart attempts before giving up
- `startupTimeout: 15000` - 15 seconds to wait for ElixirLS to start

**Disabled Features** (for performance):
- `fetchDeps: false` - Doesn't auto-fetch dependencies
- `suggestSpecs: false` - Doesn't suggest @spec annotations
- `enableTestLenses: false` - Disables test code lenses

### Customizing Configuration

To customize ElixirLS settings, edit `.lsp.json` in the plugin directory:

```json
{
  "elixir": {
    "settings": {
      "elixirLS": {
        "dialyzerEnabled": true,
        "mixEnv": "dev",
        "dialyzerWarnOpts": ["error_handling", "underspecs"],
        ...
      }
    }
  }
}
```

Available `dialyzerWarnOpts`:
- `error_handling` - Warn about improper error handling
- `no_return` - Warn about functions that never return
- `underspecs` - Warn about under-specified functions
- `unknown` - Warn about unknown functions
- `unmatched_returns` - Warn about unmatched return values

See [ElixirLS documentation](https://github.com/elixir-lsp/elixir-ls) for all available settings.

## Usage

Once the plugin is installed and ElixirLS is in your PATH, Claude Code will automatically:

1. Start the ElixirLS server when you open an Elixir file
2. Provide real-time diagnostics as you edit
3. Enable code navigation features via the LSP tool

### Using LSP Features in Claude Code

Claude Code can use the LSP integration via the LSP tool:

```elixir
# Example: Find where a function is defined
# Claude can use: LSP(operation: "goToDefinition", filePath: "lib/my_module.ex", line: 10, character: 5)

# Example: Find all references to a function
# Claude can use: LSP(operation: "findReferences", filePath: "lib/my_module.ex", line: 15, character: 8)
```

The LSP tool provides:
- `goToDefinition` - Find where a symbol is defined
- `findReferences` - Find all references to a symbol
- `hover` - Get hover information (documentation, type info)
- `documentSymbol` - Get all symbols in a document
- `workspaceSymbol` - Search for symbols across the workspace
- `goToImplementation` - Find implementations of an interface/protocol

## Troubleshooting

### ElixirLS Not Found

**Error**: `Executable not found in $PATH: elixir-ls`

**Solution**: Install ElixirLS using one of the methods above and ensure it's in your PATH.

```bash
# Verify installation
which elixir-ls

# If missing, check your PATH
echo $PATH | grep -o "[^:]*mix/escripts[^:]*"
```

### LSP Server Crashes on Startup

**Error**: LSP server keeps restarting or crashing

**Possible causes**:
1. **Dependency issues**: Run `mix deps.get` in your project
2. **Compilation errors**: Run `mix compile` to identify issues
3. **ElixirLS version**: Ensure you're using a recent version

**Debug steps**:

```bash
# Enable detailed LSP logging
claude --enable-lsp-logging

# Check logs
tail -f ~/.claude/debug/lsp-elixir.log
```

### Slow Startup or High CPU Usage

ElixirLS compiles your project on startup and runs Dialyzer analysis, which can be resource-intensive.

**Solutions**:

1. **Disable Dialyzer** (faster startup, less type checking):

```json
{
  "elixir": {
    "initializationOptions": {
      "dialyzerEnabled": false
    }
  }
}
```

2. **Use a faster mix environment**:

```json
{
  "elixir": {
    "env": {
      "MIX_ENV": "test"
    }
  }
}
```

3. **Exclude large dependencies** - Add to your project's `.elixir_ls/` config.

### Features Not Working

If LSP features aren't providing results:

1. **Check ElixirLS is running**:
```bash
ps aux | grep elixir-ls
```

2. **Verify project compiles**:
```bash
mix compile
```

3. **Check for LSP errors in logs**:
```bash
cat ~/.claude/debug/lsp-elixir.log
```

4. **Restart the LSP server**:
```bash
# In Claude Code, use:
/restart-lsp
```

### ElixirLS Version Compatibility

This plugin works with:
- **Elixir**: 1.14+ (tested with 1.19.4)
- **Erlang/OTP**: 25+ (tested with OTP 28)
- **ElixirLS**: v0.17.0+

If you encounter compatibility issues, update ElixirLS by downloading the latest release:

```bash
cd ~/bin/elixir-ls
curl -fLO https://github.com/elixir-lsp/elixir-ls/releases/latest/download/elixir-ls.zip
unzip -o elixir-ls.zip
chmod +x language_server.sh
```

## Performance Tips

1. **Use incremental compilation**: ElixirLS uses Mix's incremental compilation by default
2. **Exclude test files**: If working on large test suites, LSP can be slower
3. **Restart periodically**: If ElixirLS becomes sluggish, restart it via `/restart-lsp`
4. **Keep dependencies updated**: Newer versions of ElixirLS have performance improvements

## Advanced Configuration

### Multiple Projects with Different Settings

If you work on multiple Elixir projects with different requirements, you can:

1. **Use project-local overrides** - Create `.lsp.json` in your project root
2. **Create project-specific plugins** - Different plugins for different project types
3. **Use environment variables** - Configure via `env` in `.lsp.json`

### Integrating with Phoenix Projects

Phoenix projects work out of the box. ElixirLS understands:
- Phoenix contexts and schemas
- LiveView modules
- Router definitions
- Template files (`.heex`)

### Ecto Schema Support

ElixirLS provides enhanced support for Ecto:
- Jump to schema definitions
- Find all references to schema fields
- Validate changeset functions

## Contributing

To improve this plugin:

1. Edit `.lsp.json` for configuration changes
2. Update `README.md` with new documentation
3. Test with your Elixir projects
4. Submit feedback or issues to the SparkFlow repository

## License

MIT License - See the SparkFlow project license for details.

## Resources

- [ElixirLS Repository](https://github.com/elixir-lsp/elixir-ls)
- [Claude Code Documentation](https://code.claude.com/docs)
- [Language Server Protocol Specification](https://microsoft.github.io/language-server-protocol/)
- [SparkFlow Project](https://github.com/14hippos/sparkflow)

## Version History

### 1.0.0 (2025-12-26)

- Initial release
- ElixirLS integration with Dialyzer support
- Support for `.ex`, `.exs`, and `.heex` files
- Auto-restart on crash
- Optimized settings for Phoenix/Ecto projects

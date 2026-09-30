# Contributing

Thank you for your interest in contributing to `smart-splits-backend-tmux`!

## Development Setup

### Prerequisites (Preferred: Nix + direnv)

If you have Nix and direnv installed:

```sh
direnv allow
```

That's it! All dependencies are provided by the Nix flake.

### Prerequisites (Alternative: Manual Installation)

If you prefer to install tools manually:

```sh
# macOS
brew install neovim tmux stylua lua-language-server luajit luarocks just \
  yamlfmt prettier tombi nixfmt actionlint statix

LUAJIT_PREFIX="$(brew --prefix luajit)"
ROCKS=(--lua-version=5.1 --lua-dir="$LUAJIT_PREFIX" --local)
luarocks "${ROCKS[@]}" install busted 2.3.0
luarocks "${ROCKS[@]}" install nlua 0.3.2
eval "$(luarocks "${ROCKS[@]}" path --bin)"
```

### Running Tests

Run all checks before submitting a PR:

```sh
just check
```

This runs:
- Formatting checks (Stylua, yamlfmt, prettier, tombi, actionlint, statix)
- Selene linting
- LuaLS type checking
- Busted test suite

Individual commands:

```sh
just test             # Run both test suites
just test-core        # Hermetic tests, against a fake tmux
just test-integration # Tests that drive a real tmux server
just lint             # Run linters
just fmt-check        # Check formatting
just fmt              # Auto-format code
just typecheck        # Type checking
```

To run the tests against Neovim nightly:

```sh
nix develop .#ci-nightly --command just test
```

The nightly build is downloaded from the [nix-community binary cache](https://nix-community.org/cache/); without that
cache configured, Nix compiles Neovim from source. CI runs `nix flake update neovim-nightly-overlay` first to test the
latest nightly.

## Implementation Guidelines

### Layout

```
lua/smart-splits-backend-tmux/
├── init.lua      # the backend table core sees
├── config.lua    # defaults and setup(), inert by protocol
├── tmux.lua      # the `tmux` CLI adapter; the only module that runs processes
├── move.lua      # move(), including at_edge
├── resize.lua    # resize()
├── activate.lua  # the `@pane-is-vim` lifecycle
└── health.lua    # :checkhealth body, under a header core emits
smart-splits.tmux  # the tmux half, for TPM: writes the key bindings
tests/
├── core/         # hermetic, against the fake tmux in tests/helpers.lua
└── integration/  # against a real tmux server on a private socket
```

### Backend Protocol

This backend implements the v3 protocol:

```lua
---@class SmartSplitsBackend
---@field name string
---@field protocol_version string  -- "3.0.0"
---@field detect fun():boolean
---@field move fun(direction: SmartSplitsDirection, opts?: SmartSplitsBackendMoveOpts):boolean
---@field resize? fun(direction: SmartSplitsDirection, opts?: SmartSplitsBackendResizeOpts):boolean
---@field activate? fun()
---@field health? fun()
```

Two rules from the protocol are easy to break by accident:

- **`detect()` must be cheap and free of side effects.** No subprocesses: core resolves backends
  inside its own `setup()`, so a `detect()` that shells out delays every startup.
- **`setup()` must stay inert.** Users install several backends and list them in priority order, so
  every installed backend is configured on every startup. Initialization belongs in `activate()`,
  which only the selected backend gets.

### Type Annotations

Use LuaCATS type annotations extensively. All functions should have:
- Parameter types with `@param`
- Return types with `@return`
- Class definitions with `@class` and `@field`

Example:

```lua
---@param direction SmartSplitsDirection
---@param opts? SmartSplitsBackendMoveOpts
---@return boolean
function M.move(direction, opts)
  -- implementation
end
```

### Testing

All new functionality should include tests. Both suites use:
- Busted test framework
- nlua (Neovim Lua interpreter)
- smart-splits core's `protocol_tests` for conformance

`tests/core/*_spec.lua` runs against the fake tmux server in `tests/helpers.lua`, which records what
the backend sent and answers the queries it makes. These tests are hermetic: they never touch a real
tmux, and behave the same whether or not you run them from inside one.

`tests/integration/*_spec.lua` starts a real tmux server per test, on a private socket and with
`-f /dev/null` so no user config can interfere, and kills it afterwards. Use these for anything whose
correctness depends on how tmux actually answers, rather than on what the backend sends. They skip
themselves when `tmux` is not on the `$PATH`.

## Code Style

- Use 2-space indentation
- Single quotes for strings
- Maximum line length: 120 characters
- Sort requires alphabetically

These are enforced by Stylua, yamlfmt, prettier, tombi, actionlint, and statix.

## Pull Request Process

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run `just check` to ensure all checks pass
5. Submit a pull request

## Questions?

Open an issue if you have questions about this backend, or about the protocol it implements.

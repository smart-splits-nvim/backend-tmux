# smart-splits-backend-tmux

A [tmux](https://github.com/tmux/tmux) backend for [smart-splits.nvim](https://github.com/smart-splits-nvim/smart-splits.nvim)
v3.

Move and resize across the Neovim/tmux boundary with one set of keys: `<C-hjkl>` walks Neovim's
windows until it runs out of them, then keeps walking tmux's panes. `<M-hjkl>` resizes the same way.
At the outer edge of tmux, the movement keys can make a new tmux pane instead of stopping.

Core shipped tmux support up to v2; v3 moved every multiplexer out into its own plugin. This is that
plugin, against the [v3 protocol](https://github.com/smart-splits-nvim/smart-splits.nvim/blob/master/PROTOCOL.md).

## Installation

Two halves have to agree: this plugin, and a handful of tmux key bindings. Neither works alone.

### Neovim

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'smart-splits-nvim/smart-splits.nvim',
  opts = {
    mux = { backend = 'smart-splits-backend-tmux' },
    move = { at_edge = 'split' },
  },
  dependencies = {
    { 'smart-splits-nvim/backend-tmux', main = 'smart-splits-backend-tmux' },
  },
}
```

Backends can be listed in priority order, which is how one config travels between machines running
different terminals:

```lua
mux = { backend = { 'smart-splits-backend-tmux', 'smart-splits-backend-ghostty' } },
```

Resolution happens once, during `setup()`. Put tmux first: it is the inner multiplexer, and a
terminal backend that also detects would otherwise move the wrong panes.

> [!IMPORTANT]
> Do not lazy load smart-splits.nvim with this backend. tmux has to be told that a pane is running
> Neovim, and it is only told when the plugin loads. Until then tmux swallows `<C-hjkl>` and Neovim
> never sees the keys.

### tmux

The tmux side cannot tell a Neovim pane from a shell pane by itself. It branches on `@pane-is-vim`, a
pane-local option this backend keeps truthful for exactly as long as Neovim owns the pane. Either let
the bundled plugin write those bindings, or write them yourself.

#### With TPM

This repository doubles as a [TPM](https://github.com/tmux-plugins/tpm) plugin: `smart-splits.tmux`
at its root binds the movement and resize keys, each branching on `@pane-is-vim`.

```tmux
set -g @plugin 'smart-splits-nvim/backend-tmux'
```

Every option is optional, and the defaults match smart-splits.nvim's own:

```tmux
# what to do when the pane is against the edge of its tmux window. Mirrors
# smart-splits.nvim's `move.at_edge`, and should be kept in step with it:
#   wrap  => focus the pane on the far side (the default, and tmux's own behaviour)
#   stop  => do nothing
#   split => create a pane, inheriting the current pane's directory
set -g @smart-splits_at_edge 'wrap'

set -g @smart-splits_move_left_key  'C-h'
set -g @smart-splits_move_down_key  'C-j'
set -g @smart-splits_move_up_key    'C-k'
set -g @smart-splits_move_right_key 'C-l'

set -g @smart-splits_resize_left_key  'M-h'
set -g @smart-splits_resize_down_key  'M-j'
set -g @smart-splits_resize_up_key    'M-k'
set -g @smart-splits_resize_right_key 'M-l'

set -g @smart-splits_resize_step_size '3'
```

If you set `move = { at_edge = 'split' }` on the Neovim side, as the example above does, set the
same here:

```tmux
set -g @smart-splits_at_edge 'split'
```

Otherwise `<C-l>` makes a pane when Neovim handles it and wraps when tmux does, which is the same key
doing two different things depending on what happens to be running in the pane.

The movement keys are also bound in `copy-mode-vi`, where they move between panes directly: there is
no Neovim to defer to in copy mode, and `at_edge = 'split'` stops at the edge there rather than
splitting, since making a pane would drop out of copy mode.

The options are read once, when the plugin runs, so set them above the `run '~/.tmux/plugins/tpm/tpm'`
line, then reload with `tmux source-file ~/.config/tmux/tmux.conf`.

> [!NOTE]
> `@smart-splits_no_wrap` from v2 is gone. It meant "stop at the edge", which is now
> `@smart-splits_at_edge 'stop'`.

#### By hand

The bindings the plugin writes for `at_edge = 'split'`, if you would rather keep them in
`~/.config/tmux/tmux.conf`:

```tmux
bind -n C-h if -F '#{@pane-is-vim}' { send-keys C-h } { if -F '#{pane_at_left}'   { split-window -hb -c "#{pane_current_path}" } { select-pane -L } }
bind -n C-j if -F '#{@pane-is-vim}' { send-keys C-j } { if -F '#{pane_at_bottom}' { split-window -v  -c "#{pane_current_path}" } { select-pane -D } }
bind -n C-k if -F '#{@pane-is-vim}' { send-keys C-k } { if -F '#{pane_at_top}'    { split-window -vb -c "#{pane_current_path}" } { select-pane -U } }
bind -n C-l if -F '#{@pane-is-vim}' { send-keys C-l } { if -F '#{pane_at_right}'  { split-window -h  -c "#{pane_current_path}" } { select-pane -R } }

bind -n M-h if -F '#{@pane-is-vim}' { send-keys M-h } { resize-pane -L 3 }
bind -n M-j if -F '#{@pane-is-vim}' { send-keys M-j } { resize-pane -D 3 }
bind -n M-k if -F '#{@pane-is-vim}' { send-keys M-k } { resize-pane -U 3 }
bind -n M-l if -F '#{@pane-is-vim}' { send-keys M-l } { resize-pane -R 3 }

bind -T copy-mode-vi C-h if -F '#{pane_at_left}'   '' 'select-pane -L'
bind -T copy-mode-vi C-j if -F '#{pane_at_bottom}' '' 'select-pane -D'
bind -T copy-mode-vi C-k if -F '#{pane_at_top}'    '' 'select-pane -U'
bind -T copy-mode-vi C-l if -F '#{pane_at_right}'  '' 'select-pane -R'
```

For `at_edge = 'wrap'`, drop the inner `if -F` and bind `select-pane` directly — it wraps on its own.
For `'stop'`, keep the `if -F` but leave the then-branch empty: `if -F '#{pane_at_right}' '' 'select-pane -R'`.

### Neovim keymaps

smart-splits.nvim binds nothing on its own:

```lua
vim.keymap.set('n', '<C-h>', require('smart-splits').move_cursor_left)
vim.keymap.set('n', '<C-j>', require('smart-splits').move_cursor_down)
vim.keymap.set('n', '<C-k>', require('smart-splits').move_cursor_up)
vim.keymap.set('n', '<C-l>', require('smart-splits').move_cursor_right)

vim.keymap.set('n', '<M-h>', require('smart-splits').resize_left)
vim.keymap.set('n', '<M-j>', require('smart-splits').resize_down)
vim.keymap.set('n', '<M-k>', require('smart-splits').resize_up)
vim.keymap.set('n', '<M-l>', require('smart-splits').resize_right)
```

## Configuration

Every option has a working default; calling `setup()` is optional. Configuration is inert and idempotent.

```lua
require('smart-splits-backend-tmux').setup({
  -- whether this backend may be selected at all
  enable = true,
  -- refuse to navigate out of a zoomed tmux pane.
  disable_nav_when_zoomed = true,
  -- cells to resize by when not specified
  resize_amount = 3,
  -- milliseconds to wait for a `tmux` invocation. These run on every keypress
  -- at a window edge, so a tmux that is not answering degrades to plain Neovim
  -- movement rather than stalling the editor
  timeout = 300,
})
```

## Behaviour

**`at_edge`.** Core hands its `move.at_edge` setting to the backend first, and only applies it inside
Neovim's own layout when the backend returns `false`.

| `at_edge` | at the outer edge of tmux                                                |
| --------- | ------------------------------------------------------------------------ |
| `'stop'`  | nothing happens                                                          |
| `'wrap'`  | focus wraps to the pane on the far side, which is what `select-pane` does |
| `'split'` | a new tmux pane, inheriting the current pane's directory                 |

With a single tmux pane there is nothing to wrap to, so `'wrap'` is handed back to core, which wraps
among Neovim's windows instead.

`select-pane` wraps whether or not you asked it to, and reports success either way, so this backend
asks tmux whether the pane is against the relevant edge (`#{pane_at_left}` and friends) before acting
rather than inferring it afterwards. That is one extra `tmux` invocation per keypress that reaches an
edge, and none at all while moving within Neovim.

**Zoom.** By default, navigating out of a zoomed pane is refused. Note that a zoomed pane fills its
window, so tmux reports it against every edge: turning `disable_nav_when_zoomed` off does not make
`<C-hjkl>` leave a zoomed pane, it only skips the check.

**Nested Neovim.** If `@pane-is-vim` is already set when an instance starts, an outer Neovim owns the
pane. The inner instance leaves the marker alone, above all on the way out, so quitting it does not
leave the outer one invisible to tmux.

**Suspend.** `<C-z>` hands the keys back to the shell; resuming takes them again.

**Socket.** Every invocation targets the server named by `$TMUX` explicitly, with `-S <socket>`, so a
Neovim that inherited a stale or foreign `$TMUX` can never drive the wrong server. Under Flatpak the
call is relayed with `flatpak-spawn --host`.

## Troubleshooting

`:checkhealth smart-splits` reports which backend is in use and, under its own header, the socket,
`$TMUX_PANE`, the tmux version, the state of `@pane-is-vim`, and which tmux keys defer to Neovim by
reading it — whichever keys those turn out to be. `:checkhealth smart-splits-backend-tmux` reports
the same without going through core.

**`<C-hjkl>` does nothing in Neovim, but moves tmux panes.** `@pane-is-vim` is not set on the pane,
so tmux is swallowing the keys. Usually because smart-splits.nvim is lazy loaded, so the backend has
not run yet.

**Nothing moves, in either direction.** Check that `tmux` is on the `$PATH` Neovim inherited;
`:checkhealth smart-splits-backend-tmux` says so directly.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). `just check` runs the linters, the type checker and both test
suites; the integration suite drives a real tmux server on a private socket, and skips itself when
tmux is not installed.

## License

MIT

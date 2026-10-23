# fgo-legacy.yazi

[`fgo.yazi`](../fgo.yazi/) for **yazi 26.1.22**, i.e. yazi releases from before the 26.8.15 plugin-API rewrite. Use it where yazi can't be upgraded (e.g. the kide dev container on RHEL9). On yazi 26.9.1 or newer, use `fgo` instead.

Behavior is identical to `fgo`. With `FGO_LIST=<file>` (one `abs-path<TAB>line<TAB>col` per line), yazi opens on a directory of numbered symlinks in `$TMPDIR/fgo` (default `/tmp/fgo`), one row per position, in list order. The preview shows the real file scrolled to the line, with the line and the token at the column highlighted. `<Enter>` opens `$VISUAL`/`$EDITOR` at line:col and returns to the same row afterwards, and `<Esc>` reveals the real file in its parent directory. Without `FGO_LIST` nothing changes. See the [fgo README](../fgo.yazi/README.md) for details and caveats.

Written against the yazi **26.1.22** source (Lua 5.4) and syntax-checked with `luac5.4`. It ran in yazi 26.9.1 (list, preview, `<Enter>`, `<Esc>`), but it has **not** been run in a live 26.1.22 yazi.

Code differences to `fgo`:
- The list directory is created with an `fs.create` loop, because there is no `fs.unique` in 26.1.22.
- Visual mode is detected with `mode.is_select or mode.is_unset`, because there is no `mode.is_normal` in 26.1.22.

## Install

```sh
ya pkg add mikemoik/plugins-yazi:fgo-legacy
```

Needs `bat` for the highlighted preview; without it the built-in preview is used, unhighlighted. Also uses `sh` and `ln`.

## Setup

`~/.config/yazi/init.lua`:

```lua
require("fgo-legacy"):setup()
```

`~/.config/yazi/yazi.toml` must list this **before** other text previewers, such as search-jump-legacy's `text/*` rule:

```toml
[[plugin.prepend_previewers]]
url = "/tmp/fgo*/*"
run = "fgo-legacy"
```

(With `TMPDIR` set, use `"<TMPDIR>/fgo*/*"` instead.)

`~/.config/yazi/keymap.toml`, together with search-jump-legacy, which also binds `<Enter>`:

```toml
[mgr]
prepend_keymap = [
  { on = "<Enter>", run = "plugin fgo-legacy -- open --else=search-jump-legacy", desc = "Edit at the position (fgo list / search) / open" },
  { on = "<Esc>",   run = "plugin fgo-legacy -- leave", desc = "Leave the fgo list / escape" },
]
```

Without search-jump-legacy, drop `--else=search-jump-legacy`.

## Arguments

`open [--else=<plugin>]`, `leave`, `start`, as in [fgo](../fgo.yazi/README.md#arguments).

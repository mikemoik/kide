# search-jump-legacy.yazi

[`search-jump.yazi`](../search-jump.yazi/) for **yazi 26.1.22**, i.e. yazi releases from before the 26.8.15 plugin-API rewrite. Use it where yazi cannot be upgraded (e.g. RHEL9, whose Rust 1.92 cannot build yazi ≥ 26.5.6). On yazi 26.9.1 or newer use `search-jump` instead.

Behavior is identical to `search-jump`: in the result list of a content search (`S`), the preview opens at the first match, matches are highlighted (current one bold black on yellow, others reverse video), `n` / `b` step through them (the current match blinks at the last/first one), the position is remembered per file, long lines scroll sideways to the current match (`«` / `»` edge markers), and `<Enter>` opens `$VISUAL`/`$EDITOR` at the current match. Outside search results, preview, `n`, `b` and `<Enter>` behave as built-in. See the [search-jump README](../search-jump.yazi/README.md) for details and caveats.

Written against the yazi **26.1.22** source (Lua 5.4) and syntax-checked with `luac5.4`. It has **not** yet been run in a live 26.1.22 yazi; runtime testing happens on the kide side (board task 132).

Code differences to `search-jump`: `url.is_search` / `url.domain` instead of `url.spec.is_search` / `url.spec.domain`, and seek always delegates to `code` (the 26.1.22 seek job has no `mime`).

## Install

```sh
ya pkg add mikemoik/plugins-yazi:search-jump-legacy
```

Needs `rg` (ripgrep, already required by `S`) and `bat` for the highlighted preview; without `bat` the preview falls back to yazi's built-in one, unhighlighted.

## Setup

`~/.config/yazi/yazi.toml`:

```toml
[[plugin.prepend_previewers]]
mime = "text/*"
run  = "search-jump-legacy"

[[plugin.prepend_previewers]]
mime = "application/{mbox,javascript,wine-extension-ini,json,ndjson}"
run  = "search-jump-legacy"
```

`~/.config/yazi/keymap.toml`:

```toml
[mgr]
prepend_keymap = [
  { on = "n", run = "plugin search-jump-legacy -- next", desc = "Next match in preview (search) / next found" },
  { on = "b", run = "plugin search-jump-legacy -- prev", desc = "Previous match in preview (search) / previous found" },
  { on = "<Enter>", run = "plugin search-jump-legacy -- open", desc = "Edit at the shown match (search) / open" },
]
```

## Arguments

`next`, `prev`, `open`, as in [search-jump](../search-jump.yazi/README.md#arguments).

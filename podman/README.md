# kide in a podman container

kide without installing anything on the host except podman.
`Containerfile.kide` builds the image on top of a base image (`BASE` in
`podman/base.conf`, default Rocky Linux 9, RHEL9-compatible): kide built into
`/opt/kide` by `build-ide.sh` in a build stage, as on a normal install (the
Rust and Go toolchains stay in that stage), and the RHEL packages kide itself
uses (python3, git, file, clangd/clang-format/clang-tidy, gdb, lldb). fish is
the shell.

On the plain base it is the IDE alone. On top of **ibn-dev**, the RHEL9 build
environment from the separate ibn-dev repo (compilers, RHEL libraries, and
CMake 4, onnxruntime, ACE+TAO, OpenDDS and GDAL built by its `build-dist.sh`),
it is the complete environment; see [On top of ibn-dev](#on-top-of-ibn-dev).
The Containerfile only adds to its base, so it works on either.

Not UBI9: UBI lacks packages the EPEL ones depend on.

## Build

The last argument of `podman build` is the repo directory (the build
context); the Containerfile copies from it into the image. From an unpacked
tarball or a git checkout, run it in the repo's top directory (where
`install.sh` and `podman/` are), ~5–10 min:

    tar -xzf kide-main.tar.gz
    cd kide-main
    podman build --build-arg-file podman/base.conf -t kide -f podman/Containerfile.kide .

Without a checkout, straight from GitHub (no curl needed):

    podman build --build-arg BASE=docker.io/rockylinux/rockylinux:9 --build-arg CONF_DIR=podman/conf --build-arg KIDE_USER=default --build-arg KIDE_UID=1001 --build-arg KIDE_GID=1001 -t kide -f podman/Containerfile.kide https://github.com/kreatos/kide.git

The build stage has two layers, each reused until its inputs change:

1. IDE compile: nvim, parsers, tools (`build-ide.sh`, from `vendor/`,
   `manifest/`, `scripts/`; ~5 min)
2. config: `config/`, `yazi/`, `fish/` (`build-ide.sh --no-build`; seconds)

A config change rebuilds only layer 2, and an IDE or vendor change rebuilds both.

### On top of ibn-dev

Build ibn-dev first, in the ibn-dev repo (see its README), then kide on top:

    podman build --build-arg-file podman/base.conf --build-arg BASE=localhost/ibn-dev -t kide -f podman/Containerfile.kide .

kide then has everything ibn-dev has: run `build-dist.sh` once in the
container to build the C/C++ libraries into `/workspace/ibn-dist`. kide knows
nothing of ibn-dev: both images ship their shell config as hooks
([Shell hooks](#shell-hooks-workspacecontainer)), ibn-dev `10-ibn-dev.*`
(`~/.local/bin`, its `ibn-dist-env` once `build-dist.sh` has run), kide
`20-kide.*`; on top of each other both are placed and sourced, in fish as in
bash. A change to ibn-dev
rebuilds kide on top of it too (the whole IDE compile, ~40 min).

Keep `KIDE_USER`/`KIDE_UID`/`KIDE_GID` in `podman/base.conf` the same as in
ibn-dev's: kide reuses the user ibn-dev created and makes fish its login
shell.

### Another base image

The Containerfile names no base image and sets up no repos itself;
`podman/base.conf` and the files in its `CONF_DIR` do, and only they change
for another base (e.g. a company RHEL9 image with its own dnf repos):

- `podman/base.conf`: `BASE=<image>`, the base of both stages, read with
  `--build-arg-file` (podman ≥ 4.7). Default: `docker.io/rockylinux/rockylinux:9`.
  Without the file, `--build-arg BASE=<image>`; with neither, the build stops
  (no default).
- `CONF_DIR` in `podman/base.conf` (default `podman/conf`, relative to the
  repo root; it has to be inside the build context): `repos.sh` (below) and
  `ubi.repo` to `/etc/yum.repos.d/` (every stage, before any `dnf install`;
  the repo has an empty one, replace it with the real one on prod).
- `$CONF_DIR/repos.sh` (`podman/conf/repos.sh`): runs as root in every stage
  before any `dnf install` (on top of ibn-dev a second time, which changes
  nothing). Default: enables CRB and EPEL (Rocky's stand-in for the target
  repos). Replace it with whatever the base needs so dnf finds every package
  the Containerfile installs (e.g. copying `.repo` files into
  `/etc/yum.repos.d/`), or with an empty script if the base is ready as is.
- `KIDE_USER`, `KIDE_UID`, `KIDE_GID` in `podman/base.conf` (default
  `default`, 1001, 1001): the user the image runs as. Every step that
  installs or writes system files runs as root (`USER root` at the start of
  every stage, also when the base image defaults to another user); the last
  step switches to `KIDE_USER`. A base image that already has that user
  (e.g. `default` in Red Hat's application images, or ibn-dev) keeps it; set
  `KIDE_UID`/`KIDE_GID` to its uid/gid then (`podman run --rm <base> id default`).
  Otherwise it is created with them. The run commands below map you to it
  with `--userns=keep-id:uid=<KIDE_UID>,gid=<KIDE_GID>`: change the numbers
  there too if you change them here.

The `dnf install` steps need those repos; `build-ide.sh` itself never touches
the network. The build context is what git tracks (`.containerignore` leaves
out `.git` and `vendor.staging`).

## Run

Edit your `~/workspace` (create it once on the host: `mkdir -p ~/workspace`).

`podman/start.sh` does exactly this (it creates `~/workspace` if missing,
takes the uid/gid from `podman/base.conf` and passes on `TERM` and
`SSH_CONNECTION`). It starts fish; `kide` opens the IDE from there, so
nvim and what it runs (builds, tests, the debugger) get the shell hooks'
environment. With file arguments kide opens them right away (via fish) and
quitting it ends the container. For git over SSH it
loads your key `~/.ssh/gitlab` into an ssh-agent for the session (asking for
its passphrase, if any) and passes the agent in (with
`--security-opt label=disable`, as SELinux blocks the agent socket otherwise),
plus `~/.ssh/known_hosts` and `~/.gitconfig` read-only; all three files must
exist:

    podman/start.sh                       # fish in ~/workspace; then: kide
    podman/start.sh myproject/src/main.py # kide on a file, relative to ~/workspace

By hand (`start.sh` also adds `-e TERM -e SSH_CONNECTION`):

    podman run --rm -it --http-proxy=false --userns=keep-id:uid=1001,gid=1001 -v "$HOME/workspace:/workspace:Z" -v kide-data:/var/lib/kide kide
    podman run --rm -it --http-proxy=false --userns=keep-id:uid=1001,gid=1001 -v "$HOME/workspace:/workspace:Z" -v kide-data:/var/lib/kide kide fish -c 'kide $argv' myproject/src/main.py

- `--http-proxy=false`: podman would otherwise copy the host's proxy
  variables (`http_proxy`, `https_proxy`, `HTTP_PROXY`, `HTTPS_PROXY`,
  `ftp_proxy`, `no_proxy`, …) into the container; kide runs without them. The
  build (`podman build`) still gets them, so dnf and pip can use the proxy.
  As a fallback, the shells' hook loader unsets them too.
- `-v "$HOME/workspace:/workspace:Z"`: your `~/workspace` on the host (create it once: `mkdir -p ~/workspace`),
  mounted on `/workspace`, the container's working directory: kide and fish
  start there, whatever directory you start from. `:Z` relabels it for SELinux
  (needed on RHEL). A file argument is relative to it (e.g.
  `kide myproject/src/main.py`). The shells' hooks are in
  `~/workspace/.container/` ([Shell hooks](#shell-hooks-workspacecontainer)).
  Likewise tmux reads
  `~/workspace/.container/tmux.conf` last, if it exists, after the image's
  `/etc/tmux.conf` (mouse on).
- `-v kide-data:/var/lib/kide`: kide's data and state (undo history, shada,
  swap files, sessions, fish history) survive the container. Leave it out for
  a throwaway session. The image points `XDG_DATA_HOME`/`XDG_STATE_HOME` there
  instead of `~/.local`, so the mount point does not depend on the user's
  home.
- `--userns=keep-id:uid=1001,gid=1001`: the container runs as `KIDE_USER`
  (`default`, uid/gid 1001), not root. With **rootless** podman (your normal
  user, not `sudo podman`) this maps your host user to it, so it can write
  the project and the files it writes stay yours (podman 4.3 or newer).
  Without it, the project is owned by root inside and `default` cannot write
  it.
- Root inside for a one-off (e.g. `dnf install` to try a package): add
  `--user root` and leave out `--userns=…`; root then is you on the host.
  Not kept: the next container starts from the image again.
- git trusts every repo in the container (`safe.directory = *` in
  `/etc/gitconfig`), so it never stops with "dubious ownership", whichever
  uid the project appears as inside.
- git identity and other git settings: `/etc/gitconfig` includes
  `/workspace/.container/.gitconfig` (host: `~/workspace/.container/.gitconfig`)
  if it exists, e.g.

      [user]
          name = Your Name
          email = you@example.com

  It is read at system level, so a global config wins over it: with
  `start.sh`, the host's `~/.gitconfig` (mounted as `GIT_CONFIG_GLOBAL`)
  overrides the same keys.

The container starts fish (lazygit, yazi, cmake, gdb, … are all on `PATH`);
`kide` opens the IDE. bash instead: `… kide bash`.

## Shell hooks: /workspace/.container

The shells' config is not baked into `~/.bashrc` and `config.fish`; those
only source a loader (`/usr/local/share/container-shell/load.{sh,fish}`,
from `container-shell/`). At every shell start the loader places the hooks
every image layer ships (`/usr/local/share/container-shell/{bash,fish}/`) in
the mounted workspace, then sources every file there in name order:

| On the host | Sourced by | From |
|---|---|---|
| `~/workspace/.container/bash/10-ibn-dev.sh`, `fish/10-ibn-dev.fish` | bash, fish | the ibn-dev image (when kide is built on it) |
| `~/workspace/.container/bash/20-kide.sh`, `fish/20-kide.fish` | bash, fish | this image: `/opt/kide/bashrc`, the bundled fish config |
| `~/workspace/.container/{bash,fish}/<yours>` | bash, fish | you, e.g. `50-my.fish` |

- The image's hooks are the image's: a changed one is overwritten at the next
  shell start. Your own config goes into files of your own.
- Each image only ships its own hooks and knows nothing of the others; the
  number orders them (base images low). `container-shell/{sync.sh,load.*}`
  are the same files in kide and ibn-dev: keep them in step.
- The hooks check for what they need (`/opt/kide`, `IBN_DIST_PREFIX`), so a
  workspace shared with an ibn-dev container without kide is fine.
- `/workspace` not writable: the hooks are sourced straight from the image.
  A root shell places them too, owned by the workspace's owner.
- The loader also unsets the host's proxy variables (fallback for
  `--http-proxy=false`).

## Shell: fish

fish is the container's default shell: `$SHELL` and the login shell of
`KIDE_USER` and root, so
terminals opened in kide (`:terminal`, the terminal window) and shells started
from lazygit or yazi are fish too. It is built from source by `build-ide.sh`, like the other tools
(a normal install gets `PREFIX/bin/fish` too; its login shell stays bash).

The IDE's shell helpers live in the repo's `fish/` directory, installed to
`/opt/kide/share/kreatos-ide/fish` and sourced by the hook `20-kide.fish`
([Shell hooks](#shell-hooks-workspacecontainer)):

- `config.fish`: kide's `bin` first on `PATH`, `YAZI_CONFIG_HOME`, the
  functions
- `aliases.fish`: aliases for interactive shells

| Alias | Runs |
|---|---|
| `vi` | `kide` |
| `lg` | `lazygit` |
| `ll` | `ls -alh` |
| `ff` | pick a file with `fzf` (preview: first 200 lines), open it in `kide` |
| `ffex` | pick an exported variable with `fzf`, copy it to the clipboard (OSC 52: not in PuTTY) |

Functions (`fish/functions/`, autoloaded):

| Function | Does |
|---|---|
| `y [ARGS]` | `yazi`; quitting with `Q` cds the shell to the directory yazi was in (`q` quits without cd) |
| `fish_prompt` | the prompt: misw's mainframe starship look in plain fish (dir, git branch/status, venv, `❯`/`✗`); needs a Nerd Font for its icons |
| `tm NAME` | attach to the tmux session `NAME`, or create it: one window split top/bottom (lower helper pane 23 % of the height at creation, like the tmuxinator `ait` layout), focus in the upper pane. Inside tmux it switches to the session. |

New helpers go into `fish/` (aliases into `aliases.fish`, functions into
`functions/NAME.fish`) and the tables above;
the image has to be built again to pick them up. fish's history is in
`/var/lib/kide/share/fish` (`XDG_DATA_HOME`), so it survives the container with the `kide-data`
volume. bash still works as a fallback (`podman run … kide bash`).

fish is built without its man pages (they need Sphinx), so builtins' `--help`
has no page to show; `help` points to <https://fishshell.com/docs/current/>.

A short alias for `~/.bashrc`:

    alias kide='podman run --rm -it --http-proxy=false --userns=keep-id:uid=1001,gid=1001 -v "$HOME/workspace:/workspace:Z" -v kide-data:/var/lib/kide kide'

## VS Code dev container

For VS Code without the terminal IDE, use the ibn-dev repo's
`ibn-devcontainer` image instead (its `devcontainer/`).

The `kide` image itself also works as a VS Code dev container (Dev Containers extension)
with podman instead of docker. Not tested yet.

1. Point the extension at podman (VS Code settings):

       "dev.containers.dockerPath": "podman"

   (`docker-compose.yml` setups also need
   `"dev.containers.dockerComposePath": "podman-compose"`, a separate package.)

2. `.devcontainer/devcontainer.json` in the project:

   ```json
   {
     "name": "kide",
     "image": "localhost/kide",
     "workspaceMount": "source=${localWorkspaceFolder},target=/workspace,type=bind,Z",
     "workspaceFolder": "/workspace",
     "mounts": ["source=kide-data,target=/var/lib/kide,type=volume"],
     "runArgs": ["--userns=keep-id:uid=1001,gid=1001", "--http-proxy=false"],
     "containerUser": "default",
     "remoteUser": "default"
   }
   ```

- `Z` in `workspaceMount` relabels the project for SELinux (needed on RHEL),
  like `:Z` in `podman run`.
- `--userns=keep-id:…` maps your host user to `default` (as in
  `podman run`), so files VS Code writes into the project stay yours.
- VS Code replaces the image's entrypoint (`kide`) with its own command
  (`overrideCommand`); its integrated terminal gets fish (`$SHELL`).
- VS Code installs its server into each new container (`~/.vscode-server`),
  which repeats for every fresh container unless that dir is on a volume too.

## Limits

- Only the mounted directory is visible; paths outside it (`../other`,
  `~/notes`) are not.
- No clipboard tool in the image (no X/Wayland socket): copying out of kide
  only works where Neovim falls back to OSC 52 and the terminal allows it.
- C/C++ builds and debugging run inside the container with RHEL9's compilers,
  not the host's.
- tmux is RHEL's package, fd (`fd-find`), rg (`ripgrep`) and `bat` are EPEL's;
  everything else of kide's tools is built from source by `build-ide.sh`.
- Updating: pull/checkout the new version and build the image again.

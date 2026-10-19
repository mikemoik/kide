# 20-kide.sh — kide's bash hook. From the kide image (placed here at every
# shell start, a change is overwritten); your own config: a file of your own.
# kide's executables first, yazi with the bundled config (/opt/kide/bashrc,
# written by build-ide.sh); nothing in a container without kide that shares
# this workspace
if [ -f /opt/kide/bashrc ]; then
  . /opt/kide/bashrc
fi
# shell history in the workspace (host: ~/workspace/.container/kide/), so it
# survives the container; appended after every command, so parallel shells
# don't overwrite each other's. Skipped when /workspace is not writable.
if mkdir -p /workspace/.container/kide 2>/dev/null && [ -w /workspace/.container/kide ]; then
  HISTFILE=/workspace/.container/kide/bash_history
  HISTSIZE=10000
  HISTFILESIZE=100000
  shopt -s histappend
  [[ ${PROMPT_COMMAND:-} == *"history -a"* ]] ||
    PROMPT_COMMAND="history -a${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi

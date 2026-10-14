# 20-kide.sh — kide's bash hook. From the kide image (placed here at every
# shell start, a change is overwritten); your own config: a file of your own.
# kide's executables first, yazi with the bundled config (/opt/kide/bashrc,
# written by build-ide.sh); nothing in a container without kide that shares
# this workspace
if [ -f /opt/kide/bashrc ]; then
  . /opt/kide/bashrc
fi

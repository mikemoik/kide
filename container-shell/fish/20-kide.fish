# 20-kide.fish — kide's fish hook. From the kide image (placed here at every
# shell start, a change is overwritten); your own config: a file of your own.
# kide's fish config (PATH, YAZI_CONFIG_HOME, functions, aliases); nothing in
# a container without kide that shares this workspace
if test -f /opt/kide/share/kreatos-ide/fish/config.fish
    source /opt/kide/share/kreatos-ide/fish/config.fish
end

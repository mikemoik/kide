# 20-kide.fish — kide's fish hook. From the kide image (placed here at every
# shell start, a change is overwritten); your own config: a file of your own.
# kide's fish config (PATH, YAZI_CONFIG_HOME, functions, aliases); nothing in
# a container without kide that shares this workspace
if test -f /opt/kide/share/kreatos-ide/fish/config.fish
    source /opt/kide/share/kreatos-ide/fish/config.fish
end
# shell history in the workspace (host: ~/workspace/.container/kide/), so it
# survives the container without the kide-data volume. fish has no setting
# for the history path but follows a symlink at its usual place
# ($XDG_DATA_HOME/fish/fish_history); a history already there moves over once.
# Skipped when /workspace is not writable.
if mkdir -p /workspace/.container/kide 2>/dev/null; and test -w /workspace/.container/kide
    set -l kide_hist /workspace/.container/kide/fish_history
    set -l data_dir (set -q XDG_DATA_HOME; and echo $XDG_DATA_HOME; or echo ~/.local/share)/fish
    set -l link $data_dir/fish_history
    if test (path resolve $link) != $kide_hist
        mkdir -p $data_dir
        if test -f $link; and not test -L $link; and not test -e $kide_hist
            mv $link $kide_hist
        end
        ln -sfn $kide_hist $link
    end
end

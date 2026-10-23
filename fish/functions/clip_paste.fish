# clip_paste: print the clipboard text. kide version: the clipboard is tmux's
# paste buffer (a mouse selection in tmux copies there, /etc/tmux.conf has
# mouse on); PuTTY can't hand its clipboard to programs in the terminal.
function clip_paste --description 'Print the clipboard text (kide: tmux paste buffer)'
    tmux save-buffer - 2>/dev/null
end

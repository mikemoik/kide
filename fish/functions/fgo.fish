# fgo [-p|--print]: find the file positions (path:line[:col], path(line,col),
# python's File "path", line N) in the clipboard (clip_paste) — compiler errors,
# tracebacks, rg output — and list them in yazi (fgo-legacy.yazi reads $FGO_LIST:
# one "abs-path<TAB>line<TAB>col" row per position, col may be empty, in the
# order found). Paths that don't exist as given are matched by their longest
# suffix against the files below $PWD. -p prints the positions instead.
function fgo --description 'List the file:line[:col] positions found in the clipboard in yazi'
    argparse p/print -- $argv
    or return

    set -l text (clip_paste | string replace -ra '\e\[[0-9;?]*[a-zA-Z]' '' | string replace -ra '\w+://\S+' '')
    if not string length -q -- $text
        echo 'fgo: clipboard is empty' >&2
        return 1
    end

    set -l paths
    set -l lines
    set -l cols
    for l in $text
        for re in 'File "(?<p>[^"]+)", line (?<n>\d+)(?<c>)' \
                '(?<p>[^\s"\'<>|()]+)\((?<n>\d+)(?:,(?<c>\d+))?\)' \
                '(?<p>[^\s"\'<>|():,]+):(?<n>\d+)(?::(?<c>\d+))?'
            set -l p
            set -l n
            set -l c
            string match -qra -- $re $l
            or continue
            set -a paths $p
            set -a lines $n
            set -a cols $c
        end
    end

    set -l files # all files below $PWD, listed on first need
    set -l rows
    for i in (seq (count $paths))
        set -l p (string replace -r '^~(?=/|$)' $HOME -- $paths[$i])
        string match -qr '[^0-9]' -- $p; or continue # a time like 12:34:56
        set -l hits
        if test -f "$p"
            set hits (path resolve -- $p)
        else
            if not set -q files[1]
                set files (fd --type f --hidden --exclude .git --absolute-path . $PWD)
            end
            set -l parts (string split / -- $p | string match -v -r '^\.{0,2}$')
            for j in (seq (count $parts))
                set -l suffix /(string join / -- $parts[$j..-1])
                set hits (string match -e -- $suffix $files | string match -er -- (string escape --style=regex -- $suffix)'$')
                set -q hits[1]; and break
            end
        end
        for h in $hits
            set -l row (string join \t -- $h $lines[$i] $cols[$i])
            contains -- $row $rows; or set -a rows $row
        end
    end

    if not set -q rows[1]
        echo 'fgo: no file positions found in the clipboard' >&2
        return 1
    end
    if set -q _flag_print
        string replace -r '\t$' '' -- $rows | string replace -a \t :
        return
    end
    set -l list (mktemp -t fgo.XXXXXX)
    printf '%s\n' $rows >$list
    FGO_LIST=$list y
    rm -f -- $list
end

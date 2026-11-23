#!/bin/sh
# search-files.sh — recursive name search for the generic file picker.
#
# Usage: search-files.sh <directory> <query>
#
# Prints the same tab-separated records as list-files.sh, in the order they are
# found so the picker can show partial results while the worker is still
# running:
#   dir<TAB><path>
#   file<TAB><path>
#
# Every entry below <directory> whose name contains <query> matches, ignoring
# case; the query is matched literally (`*`, `?` and `[` are not globs here).
# Hidden entries are included because the normal listing shows them too, and
# symlinks to directories are reported as dir records but never descended into,
# so a link cycle cannot hang the worker.
#
# At most 400 records are printed. When the tree holds more matches a final
# `limit<TAB>400` record tells the picker the list was truncated.
#
# The picker stops the worker as soon as the query or folder changes. Like
# list-files.sh, this wrapper first kills a worker left behind by a previous
# shell (same starting folder, any query) so two searches cannot compete.

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <directory> <query>" >&2
    exit 2
fi

src=$1
query=$2

if [ ! -d "$src" ]; then
    echo "search-files.sh: not a directory: $src" >&2
    exit 1
fi

if [ -z "$query" ]; then
    exit 0
fi

limit=400

# Один `pgrep -f` замінює повний обхід /proc (по форку `tr` на кожен процес у
# системі). Шаблон звужує пошук до воркерів цього скрипта, а кожен знайдений pid
# усе одно звіряється з /proc/<pid>/cmdline, перш ніж його зупинити.
pids=$(pgrep -f -- '^(.*/)?sh .*search-files\.sh( |$)' 2>/dev/null) || pids=""
for pid in $pids; do
    [ "$pid" = "$$" ] && continue
    args=$(tr '\0' '\n' 2>/dev/null < "/proc/$pid/cmdline") || continue
    set -f
    old_ifs=$IFS
    IFS='
'
    set -- $args
    IFS=$old_ifs
    set +f
    [ "$#" -eq 4 ] || continue
    [ "${1##*/}" = "sh" ] || continue
    [ "${2##*/}" = "search-files.sh" ] || continue
    [ "$3" = "$src" ] || continue
    kill "$pid" 2>/dev/null || true
done

# Escape the glob characters so the typed text is matched literally by -iname.
pattern=$(printf '%s' "$query" | sed 's/[][*?\\]/\\&/g')

find "$src" -mindepth 1 \( -type d -o -type f -o -type l \) \
    -iname "*$pattern*" -print 2>/dev/null \
    | {
        count=0
        while IFS= read -r path; do
            [ -n "$path" ] || continue
            count=$((count + 1))
            if [ "$count" -gt "$limit" ]; then
                printf 'limit\t%s\n' "$limit"
                break
            fi
            if [ -d "$path" ]; then
                printf 'dir\t%s\n' "$path"
            else
                printf 'file\t%s\n' "$path"
            fi
        done
    }

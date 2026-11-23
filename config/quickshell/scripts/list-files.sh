#!/bin/sh
# list-files.sh — one directory level for the generic file picker.
#
# Usage: list-files.sh <directory>
#
# Prints one tab-separated record per entry:
#   dir<TAB><path>
#   file<TAB><path>
#
# Directories (including symlinks that point at directories) come first, then
# files, each group sorted with LC_ALL=C.  Hidden entries are included on
# purpose: a file picker must be able to reach ~/.config and friends.
#
# Like wallpaper-thumbnails.sh, the worker first stops an identical worker left
# behind by a previous shell.  The picker also SIGTERMs the worker when the
# user switches folders, so two directories can never mix their records.

set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <directory>" >&2
    exit 2
fi

src=$1

if [ ! -d "$src" ]; then
    echo "list-files.sh: not a directory: $src" >&2
    exit 1
fi

# Один `pgrep -f` замінює повний обхід /proc (по форку `tr` на кожен процес у
# системі). Шаблон звужує пошук до воркерів цього скрипта, а кожен знайдений pid
# усе одно звіряється з /proc/<pid>/cmdline, перш ніж його зупинити.
pids=$(pgrep -f -- '^(.*/)?sh .*list-files\.sh( |$)' 2>/dev/null) || pids=""
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
    [ "$#" -eq 3 ] || continue
    [ "${1##*/}" = "sh" ] || continue
    [ "${2##*/}" = "list-files.sh" ] || continue
    [ "$3" = "$src" ] || continue
    kill "$pid" 2>/dev/null || true
done

# Real directories first.
find "$src" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null \
    | LC_ALL=C sort \
    | while IFS= read -r path; do
        [ -n "$path" ] || continue
        printf 'dir\t%s\n' "$path"
    done

# Everything else.  `-d` follows symlinks, so a link to a folder is navigable.
find "$src" -mindepth 1 -maxdepth 1 ! -type d -print 2>/dev/null \
    | LC_ALL=C sort \
    | while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path" ]; then
            printf 'dir\t%s\n' "$path"
        else
            printf 'file\t%s\n' "$path"
        fi
    done

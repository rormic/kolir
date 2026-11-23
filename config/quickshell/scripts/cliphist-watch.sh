#!/bin/sh
# cliphist-watch.sh — один слухач буфера обміну для одного MIME-типу.
#
# Quickshell запускає слухача як дочірній процес Quickshell.Io Process, але
# завершення самого Quickshell не завершує дітей: wl-paste переходить під PID 1,
# зберігає з'єднання з Wayland і далі пише в cliphist. Тому кожен перезапуск
# оболонки додавав би ще одну пару слухачів. Новий слухач спершу зупиняє
# слухача, що лишився від попередньої оболонки, і лише потім заступає на його
# місце.
#
# Використання: cliphist-watch.sh text|image

set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 text|image" >&2
    exit 2
fi

type=$1
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
store="$script_dir/cliphist-store.py"

# Порівнюємо повний argv, щоб зупинити лише ідентичний wl-paste --watch, а не
# інший процес wl-paste чи оболонку, яка просто згадує цю команду. Один
# `pgrep -f` замінює повний обхід /proc (по форку `tr` на кожен процес у
# системі); знайдений pid усе одно звіряється з /proc/<pid>/cmdline.
pids=$(pgrep -f -- '^(.*/)?wl-paste --type [^ ]* --watch .*cliphist-store\.py$' 2>/dev/null) || pids=""
for pid in $pids; do
    [ "$pid" = "$$" ] && continue
    args=$(tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null) || continue
    set -f
    old_ifs=$IFS
    IFS='
'
    set -- $args
    IFS=$old_ifs
    set +f
    [ "$#" -eq 5 ] || continue
    [ "${1##*/}" = "wl-paste" ] || continue
    [ "$2" = "--type" ] || continue
    [ "$3" = "$type" ] || continue
    [ "$4" = "--watch" ] || continue
    [ "$5" = "$store" ] || continue
    kill "$pid" 2>/dev/null || true
done

exec wl-paste --type "$type" --watch "$store"

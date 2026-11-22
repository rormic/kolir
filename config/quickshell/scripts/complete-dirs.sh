#!/bin/sh
# complete-dirs.sh — підказки тек для поля шляху в панелі шпалер.
#
# Використання: complete-dirs.sh <поточна-тека> <введений-шлях>
#
# Друкує до 8 існуючих тек, чия назва починається з останнього компонента
# введеного шляху, по одному абсолютному шляху на рядок. Підтримує `~`,
# абсолютні та відносні шляхи; приховані теки показуються лише тоді, коли
# сам префікс починається з крапки. Помилки читання батьківської теки просто
# дають порожній список.

set -u

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <current-dir> <typed-path>" >&2
    exit 2
fi

base=$1
typed=$2

# Той самий ~, що й у normalizePath() у WallpaperPicker.qml.
case $typed in
    "~")
        typed=$HOME
        ;;
    "~/"*)
        typed=$HOME/${typed#"~/"}
        ;;
esac

# Відносний шлях рахуємо від теки, яку зараз переглядає панель.
case $typed in
    /*) ;;
    *) typed=$base/$typed ;;
esac

# Розділяємо на батьківську теку та останній компонент.
case $typed in
    /)
        parent=/
        prefix=
        ;;
    */)
        parent=${typed%/}
        prefix=
        ;;
    *)
        parent=${typed%/*}
        prefix=${typed##*/}
        [ -n "$parent" ] || parent=/
        ;;
esac

parent=$(readlink -f -- "$parent" 2>/dev/null) || exit 0
[ -d "$parent" ] && [ -r "$parent" ] || exit 0

case $prefix in
    .*) show_hidden=1 ;;
    *) show_hidden=0 ;;
esac

find "$parent" -mindepth 1 -maxdepth 1 -print 2>/dev/null \
    | LC_ALL=C sort \
    | while IFS= read -r path; do
        [ -d "$path" ] || continue
        name=${path##*/}
        if [ "$show_hidden" -eq 0 ]; then
            case $name in
                .*) continue ;;
            esac
        fi
        case $name in
            "$prefix"*) printf '%s\n' "$path" ;;
        esac
    done | head -n 8

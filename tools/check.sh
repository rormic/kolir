#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
#
# Repository checks: QML lint, Python byte-compilation and shell syntax.
#
# .github/workflows/check.yml runs this script inside an archlinux container, so
# it must stay POSIX sh and only depend on tools that are installed there (a
# missing linter is reported as a skip instead of an error).
#
# Usage: sh tools/check.sh
# Exit status: 0 when every available category passes, 1 on the first category
# with errors. Later categories are not run after a failure, and every failing
# file in the current one is listed.

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P) || {
	echo "check: cannot resolve the script directory" >&2
	exit 1
}

# Shared root resolution: $KOLIR_ROOT, then the checkout/package around
# config/hypr/scripts, then /usr/share/kolir.
. "$SCRIPT_DIR/../config/hypr/scripts/lib/root.sh" || {
	echo "check: cannot load config/hypr/scripts/lib/root.sh" >&2
	exit 1
}

ROOT=$(kolir_root "$SCRIPT_DIR/../config/hypr/scripts") || {
	echo "check: cannot find the kolir root (set KOLIR_ROOT)" >&2
	exit 1
}

cd "$ROOT" || exit 1

WORK=$(mktemp -d "${TMPDIR:-/tmp}/kolir-check.XXXXXX") || {
	echo "check: cannot create a temporary directory" >&2
	exit 1
}
cleanup() { rm -rf "$WORK"; }
trap cleanup 0
trap 'cleanup; exit 1' 1 2 15

ok() { printf 'ok    %s\n' "$1"; }
skip() { printf 'skip  %s\n' "$1"; }

fail() {
	# $1 is the category label, $2 the captured log.
	printf '\nFAIL  %s\n' "$1" >&2
	sed 's/^/  /' "$2" >&2
	printf 'check: %s failed (see the output above)\n' "$1" >&2
	exit 1
}

printf 'check: %s\n' "$ROOT"

# --- QML lint ---------------------------------------------------------------
# qmllint exits nonzero only on real errors; the known `missing-property` and
# `unqualified` warnings keep the exit code at 0 and are baseline noise.
QML_FILES=$(find config/quickshell -type f -name '*.qml' | sort)

if [ -z "$QML_FILES" ]; then
	printf 'FAIL  qmllint\n  no QML files found under config/quickshell\n' >&2
	exit 1
fi

if [ -x /usr/lib/qt6/bin/qmllint ]; then
	QMLLINT=/usr/lib/qt6/bin/qmllint
elif command -v qmllint >/dev/null 2>&1; then
	QMLLINT=$(command -v qmllint)
else
	QMLLINT=
fi

if [ -z "$QMLLINT" ]; then
	skip "qmllint (not installed)"
else
	if ! "$QMLLINT" $QML_FILES >"$WORK/qmllint.log" 2>&1; then
		fail "qmllint" "$WORK/qmllint.log"
	fi
	ok "qmllint: $(printf '%s\n' "$QML_FILES" | wc -l | tr -d ' ') QML files"
fi

# --- Python byte-compilation ------------------------------------------------
# PYTHONPYCACHEPREFIX keeps py_compile from writing __pycache__ into the tree.
PY_FILES=$(
	{
		printf '%s\n' tools/kolir.py
		find config/quickshell/scripts -type f -name '*.py' | sort
	} | sort
)

if ! command -v python3 >/dev/null 2>&1; then
	skip "py_compile (python3 not installed)"
else
	if ! PYTHONPYCACHEPREFIX="$WORK/pycache" python3 -m py_compile $PY_FILES >"$WORK/pycompile.log" 2>&1; then
		fail "py_compile" "$WORK/pycompile.log"
	fi
	ok "py_compile: $(printf '%s\n' "$PY_FILES" | wc -l | tr -d ' ') Python files"
fi

# --- Shell syntax -----------------------------------------------------------
# The interpreter comes from each shebang: sh (brightness.sh, screen-record.sh,
# the Quickshell helpers, bin/kolir), zsh (generate-colors.sh,
# set-wallpaper.sh, random-wallpaper.sh, select-wallpaper.sh) and bash
# (toggle-theme.sh).
SHELL_FILES=$(
	{
		printf '%s\n' bin/kolir
		find config/hypr/scripts config/quickshell/scripts -type f -name '*.sh'
	} | sort
)

sh_count=0
zsh_count=0
bash_count=0
missing=

for file in $SHELL_FILES; do
	interp=sh
	case $(head -n 1 "$file") in
	*zsh*) interp=zsh ;;
	*bash*) interp=bash ;;
	esac

	if ! command -v "$interp" >/dev/null 2>&1; then
		missing="$missing $file"
		continue
	fi

	if ! err=$("$interp" -n "$file" 2>&1); then
		{
			printf '%s (%s -n):\n' "$file" "$interp"
			printf '%s\n' "$err"
		} >>"$WORK/shell.log"
	fi

	case $interp in
	sh) sh_count=$((sh_count + 1)) ;;
	zsh) zsh_count=$((zsh_count + 1)) ;;
	bash) bash_count=$((bash_count + 1)) ;;
	esac
done

if [ -s "$WORK/shell.log" ]; then
	fail "shell syntax" "$WORK/shell.log"
fi

[ -n "$missing" ] && skip "shell syntax for missing interpreter:$missing"

if [ $((sh_count + zsh_count + bash_count)) -eq 0 ]; then
	printf 'FAIL  shell syntax\n  no shell scripts found\n' >&2
	exit 1
fi

summary="sh -n: $sh_count"
[ "$zsh_count" -gt 0 ] && summary="$summary, zsh -n: $zsh_count"
[ "$bash_count" -gt 0 ] && summary="$summary, bash -n: $bash_count"
ok "shell syntax ($summary)"

printf 'check: all checks passed\n'

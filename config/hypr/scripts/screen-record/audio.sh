#!/bin/sh
# Audio helpers for screen-record.sh. Sourced after the recorder state
# variables are defined; all names and behaviour match the original script.

cleanup_audio_mix() {
	[ -f "$AUDIO_MODULES_FILE" ] || return 0
	while IFS= read -r module_id; do
		[ -n "$module_id" ] || continue
		pactl unload-module "$module_id" >/dev/null 2>&1 || true
	done <"$AUDIO_MODULES_FILE"
	rm -f "$AUDIO_MODULES_FILE"
}

default_sink_monitor() {
	sink=$(pactl get-default-sink 2>/dev/null)
	[ -n "$sink" ] || return 0
	candidate="$sink.monitor"
	if pactl list short sources 2>/dev/null | awk -v m="$candidate" '$2 == m { found = 1 } END { exit !found }'; then
		echo "$candidate"
	fi
}

default_microphone() {
	source=$(pactl get-default-source 2>/dev/null)
	[ -n "$source" ] || return 0
	if pactl list short sources 2>/dev/null | awk -v m="$source" '$2 == m { found = 1 } END { exit !found }'; then
		echo "$source"
	fi
}

wait_for_source() {
	source="$1"
	i=0
	while [ "$i" -lt 20 ]; do
		if pactl list short sources 2>/dev/null | awk -v s="$source" '$2 == s { found = 1 } END { exit !found }'; then
			return 0
		fi
		sleep 0.05
		i=$((i + 1))
	done
	return 1
}

# Тимчасовий null-sink із двома loopback-джерелами (система + мікрофон).
# Модулі живуть лише під час запису; cleanup_audio_mix вивантажує їх.
setup_audio_mix() {
	mix_sink=$(pactl get-default-sink 2>/dev/null)
	mix_mic=$(pactl get-default-source 2>/dev/null)
	[ -n "$mix_sink" ] && [ -n "$mix_mic" ] || return 1

	: >"$AUDIO_MODULES_FILE" || return 1

	mix_id=$(pactl load-module module-null-sink sink_name="$MIX_SINK" rate=48000 2>/dev/null) || {
		cleanup_audio_mix
		return 1
	}
	echo "$mix_id" >>"$AUDIO_MODULES_FILE"

	if ! wait_for_source "$MIX_SINK.monitor"; then
		cleanup_audio_mix
		return 1
	fi

	mix_id=$(pactl load-module module-loopback source="$mix_sink.monitor" sink="$MIX_SINK" latency_msec=30 2>/dev/null) || {
		cleanup_audio_mix
		return 1
	}
	echo "$mix_id" >>"$AUDIO_MODULES_FILE"

	mix_id=$(pactl load-module module-loopback source="$mix_mic" sink="$MIX_SINK" latency_msec=30 2>/dev/null) || {
		cleanup_audio_mix
		return 1
	}
	echo "$mix_id" >>"$AUDIO_MODULES_FILE"

	echo "$MIX_SINK.monitor"
	return 0
}

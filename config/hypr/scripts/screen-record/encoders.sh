#!/bin/sh
# Encoder and quality helpers for screen-record.sh. Sourced after the
# recorder state variables are defined; all names and behaviour match the
# original script.

has_encoder() {
	ffmpeg -hide_banner -encoders 2>/dev/null | grep -q "[[:space:]]$1[[:space:]]"
}

# Наявність енкодера в ffmpeg ще не означає, що GPU його підтримує
# (наприклад, av1_nvenc є у збірці, але не на всіх відеокартах).
encoder_usable() {
	case "$1" in
	*nvenc)
		ffmpeg -hide_banner -loglevel error \
			-f lavfi -i color=c=black:s=256x256:r=1 -frames:v 1 \
			-c:v "$1" -f null - >/dev/null 2>&1
		;;
	*) return 0 ;;
	esac
}

encoder_for() {
	case "$OPT_CODEC" in
	hevc)
		if has_encoder hevc_nvenc && encoder_usable hevc_nvenc; then
			echo hevc_nvenc
		elif has_encoder libx265; then
			echo libx265
		fi
		;;
	av1)
		if has_encoder av1_nvenc && encoder_usable av1_nvenc; then
			echo av1_nvenc
		elif has_encoder libsvtav1; then
			echo libsvtav1
		elif has_encoder libaom-av1; then
			echo libaom-av1
		fi
		;;
	*)
		if has_encoder h264_nvenc && encoder_usable h264_nvenc; then
			echo h264_nvenc
		elif has_encoder libx264; then
			echo libx264
		fi
		;;
	esac
}

quality_bitrate() {
	case "$OPT_QUALITY" in
	low) echo "8M" ;;
	high) echo "40M" ;;
	max) echo "80M" ;;
	*) echo "20M" ;;
	esac
}

quality_crf() {
	# $1 = encoder
	case "$1" in
	libx264) case "$OPT_QUALITY" in low) echo 28 ;; medium) echo 23 ;; high) echo 18 ;; max) echo 14 ;; esac ;;
	libx265) case "$OPT_QUALITY" in low) echo 30 ;; medium) echo 26 ;; high) echo 22 ;; max) echo 18 ;; esac ;;
	*) case "$OPT_QUALITY" in low) echo 38 ;; medium) echo 32 ;; high) echo 26 ;; max) echo 20 ;; esac ;;
	esac
}

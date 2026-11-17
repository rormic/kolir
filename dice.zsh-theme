# ~/.oh-my-zsh/custom/themes/dice.zsh-theme
# або встав у ~/.zshrc, якщо без oh-my-zsh
#
# Один рядок, без фонових заливок (капсули з %K давали дивні
# білі обводки в foot) — чистий кольоровий текст + іконки.
# Кольори — лише зі стандартної 16-ANSI палітри (0-15), щоб
# усе підхоплювало Material 3 акценти від matugen і саме
# перефарбовувалось під нові шпалери.
#
# Потребує Nerd Font для іконок (  🎲).

zmodload zsh/datetime 2>/dev/null
setopt PROMPT_SUBST

typeset -g _CMD_START=
typeset -g _CMD_DURATION=

preexec() {
  _CMD_START=$EPOCHREALTIME
}

precmd() {
  LAST_EXIT_CODE=$?
  if [[ -n $_CMD_START ]]; then
    _CMD_DURATION=$(( EPOCHREALTIME - _CMD_START ))
  else
    _CMD_DURATION=
  fi
  _CMD_START=
}

_fmt_duration() {
  local d=$1
  if (( d < 1 )); then
    printf "%dms" $(( d * 1000 ))
  elif (( d < 60 )); then
    printf "%.1fs" "$d"
  else
    printf "%dm%02ds" $(( d/60 )) $(( d%60 ))
  fi
}

_seg_time() {
  [[ -z $_CMD_DURATION ]] && return
  echo "%F{8}⏱ $(_fmt_duration "$_CMD_DURATION")%f "
}

_seg_dir() {
  echo "%F{4}%B%~%b%f"
}

_seg_git() {
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || return
  local dot="%F{2}"
  [[ -n $(git status --porcelain 2>/dev/null) ]] && dot="%F{3}"
  echo " %F{8}%f${dot}●%f %F{5}${branch}%f"
}

_seg_venv() {
  [[ -n "$VIRTUAL_ENV" ]] || return
  echo " %F{2}(${VIRTUAL_ENV:t})%f"
}

_seg_dice() {
  [[ $LAST_EXIT_CODE -eq 0 ]] && echo "%F{2}🎲%f" || echo "%F{1}🎲%f"
}

PROMPT='$(_seg_time)$(_seg_dir)$(_seg_git)$(_seg_venv) $(_seg_dice) '
RPROMPT='%(?..%F{1}✘ %? %f)%F{8}%*%f'

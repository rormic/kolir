#!/usr/bin/env bash
set -euo pipefail

# kolir install/bootstrap script
# - Can be run via curl: curl -fsSL https://raw.githubusercontent.com/rormic/kolir/main/install.sh | bash
#   In that mode it will clone/update the repository and run the installer from it.
# - Checks dependencies and installs missing ones (Arch/pacman)
# - Installs AUR helper if needed (paru default, optional yay)
# - Installs Oh My Zsh, plugins, and links the dice theme
# - Shows a full action plan before making changes and asks for confirmation
#
# Config deployment targets a ready system: foot/hypr via config loaders,
# matugen/mpv/zshrc/scripts linked to the repo, with backups.

KOLIR_REPO_URL="${KOLIR_REPO_URL:-https://github.com/rormic/kolir.git}"
KOLIR_BRANCH="${KOLIR_BRANCH:-}" # empty = remote default branch
KOLIR_DIR="${KOLIR_DIR:-$HOME/.local/share/kolir}"

# Detect whether we are running from inside the kolir repo checkout.
_self_dir=""
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != "bash" && -e "${BASH_SOURCE[0]}" ]]; then
  _self_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -n "$_self_dir" && -f "$_self_dir/config/matugen/config.toml" && -f "$_self_dir/dice.zsh-theme" ]]; then
  BOOTSTRAP_MODE="no"
  REPO_DIR="$_self_dir"
else
  BOOTSTRAP_MODE="yes"
  REPO_DIR="$KOLIR_DIR"
fi

ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# --- formatting ---
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
  YELLOW=$'\033[33m'; BLUE=$'\033[34m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
else
  BOLD='' DIM='' RED='' GREEN='' YELLOW='' BLUE='' CYAN='' RESET=''
fi

info()  { printf '%s[info]%s  %s\n' "$BLUE" "$RESET" "$*"; }
ok()    { printf '%s[ok]%s    %s\n' "$GREEN" "$RESET" "$*"; }
warn()  { printf '%s[warn]%s  %s\n' "$YELLOW" "$RESET" "$*"; }
err()   { printf '%s[err]%s   %s\n' "$RED" "$RESET" "$*" >&2; }
step()  { printf '\n%s==> %s%s\n' "$BOLD" "$*" "$RESET"; }

ask_yn() {
  local prompt="$1" default="${2:-N}" reply
  local suffix="[y/N]"
  [[ "$default" == "Y" ]] && suffix="[Y/n]"
  if [[ -t 0 ]]; then
    read -r -p "$prompt $suffix " reply || true
  elif [[ -r /dev/tty ]]; then
    read -r -p "$prompt $suffix " reply </dev/tty || true
  else
    [[ "$default" == "Y" ]] && return 0 || return 1
  fi
  reply="${reply:-$default}"
  [[ "$reply" =~ ^[Yy]$ ]]
}

have() { command -v "$1" >/dev/null 2>&1; }
pkg_installed() { pacman -Qi "$1" >/dev/null 2>&1; }

# --- package sets (confirmed plan) ---
REPO_PKGS=(
  # base/cli
  zsh git base-devel curl wget python jq wl-clipboard grim slurp
  brightnessctl ddcutil libnotify playerctl zenity nautilus
  pipewire pipewire-pulse wireplumber
  # wm/session/media/record
  hyprland hyprsunset foot mpv wf-recorder
  # ui/theme/wallpaper (official repos)
  quickshell awww matugen
  # fonts & icons (bar uses Material Symbols Rounded; app icons need an icon theme)
  ttf-googlesanscode-nerd ttf-dejavu ttf-dejavu-nerd ttf-material-symbols-variable
  papirus-icon-theme hicolor-icon-theme
)

AUR_PKGS=(
  # cursor theme used by hyprland user config example (Mocu-White-Left)
  mocu-xcursor
)

WARN_ONLY_PKGS=(docker docker-compose go)
WARN_ONLY_LABELS=("docker (zsh plugin)" "docker-compose (zsh plugin)" "go/golang (zsh plugin)")

OMZ_DIR="$HOME/.oh-my-zsh"
OMZ_REPO="https://github.com/ohmyzsh/ohmyzsh.git"
PLUGINS=(
  "zsh-autosuggestions|https://github.com/zsh-users/zsh-autosuggestions"
  "zsh-syntax-highlighting|https://github.com/zsh-users/zsh-syntax-highlighting.git"
)
THEME_NAME="dice"
THEME_SRC="$REPO_DIR/dice.zsh-theme"

# --- state / plan ---
MISSING_REPO_PKGS=()
MISSING_AUR_PKGS=()
MISSING_WARN_PKGS=()
ACTIONS=()
MANUAL=()
AUR_HELPER=""
NEED_AUR_BOOTSTRAP="no"
PLAN_INSTALL_OMZ="no"
PLAN_PLUGINS=()
PLAN_THEME_LINK="no"
PLAN_DIRS=()
PLAN_DEPLOY=()

preflight() {
  step "Preflight"
  if [[ $EUID -eq 0 ]]; then
    warn "Running as root. It is recommended to run as a regular user (sudo will be requested when needed)."
  fi
  if ! have pacman; then
    err "pacman not found. This script is intended for Arch Linux."
    exit 1
  fi
  if [[ "$BOOTSTRAP_MODE" == "no" ]]; then
    if [[ ! -d "$REPO_DIR/.git" || ! -d "$REPO_DIR/config" ]]; then
      warn "This does not look like a full kolir checkout: $REPO_DIR"
    fi
    for c in git curl; do
      if ! have "$c"; then
        warn "Required tool '$c' is missing — it will be installed with dependencies (if you confirm)."
      fi
    done
    ok "Repository: $REPO_DIR"
  else
    info "Bootstrap mode (running outside the repository, e.g. via curl)"
    info "Target repository directory: $REPO_DIR"
    info "Source: $KOLIR_REPO_URL${KOLIR_BRANCH:+ (branch: $KOLIR_BRANCH)}"
  fi
}

scan_packages() {
  step "Dependency check (packages)"
  MISSING_REPO_PKGS=()
  for p in "${REPO_PKGS[@]}"; do
    if pkg_installed "$p"; then
      printf '  %s%-28s%s %s\n' "$GREEN" "$p" "$RESET" "installed"
    else
      printf '  %s%-28s%s %s\n' "$YELLOW" "$p" "$RESET" "missing (repo)"
      MISSING_REPO_PKGS+=("$p")
    fi
  done

  MISSING_AUR_PKGS=()
  for p in "${AUR_PKGS[@]:-}"; do
    [[ -z "$p" ]] && continue
    if pkg_installed "$p"; then
      printf '  %s%-28s%s %s\n' "$GREEN" "$p" "$RESET" "installed"
    else
      printf '  %s%-28s%s %s\n' "$YELLOW" "$p" "$RESET" "missing (AUR)"
      MISSING_AUR_PKGS+=("$p")
    fi
  done

  MISSING_WARN_PKGS=()
  local i=0
  for p in "${WARN_ONLY_PKGS[@]}"; do
    if pkg_installed "$p" || have "$p"; then
      printf '  %s%-28s%s %s\n' "$GREEN" "${WARN_ONLY_LABELS[$i]}" "$RESET" "present"
    else
      printf '  %s%-28s%s %s\n' "$YELLOW" "${WARN_ONLY_LABELS[$i]}" "$RESET" "missing (warning only)"
      MISSING_WARN_PKGS+=("${WARN_ONLY_LABELS[$i]}")
    fi
    i=$((i+1))
  done
}

scan_omz() {
  step "Oh My Zsh / plugins / theme check"
  if [[ -d "$OMZ_DIR" ]]; then
    ok "Oh My Zsh: installed ($OMZ_DIR)"
  else
    warn "Oh My Zsh: not installed"
    PLAN_INSTALL_OMZ="yes"
  fi

  PLAN_PLUGINS=()
  local entry name url target
  for entry in "${PLUGINS[@]}"; do
    name="${entry%%|*}"; url="${entry#*|}"
    target="$ZSH_CUSTOM_DIR/plugins/$name"
    if [[ -d "$target" ]]; then
      ok "Plugin: $name (present)"
    else
      warn "Plugin: $name (missing)"
      PLAN_PLUGINS+=("$entry")
    fi
  done

  local theme_dst="$ZSH_CUSTOM_DIR/themes/${THEME_NAME}.zsh-theme"
  if [[ ! -f "$THEME_SRC" ]]; then
    warn "Theme file not found in repo: $THEME_SRC"
  elif [[ -L "$theme_dst" || -f "$theme_dst" ]]; then
    local cur=""
    [[ -L "$theme_dst" ]] && cur="$(readlink -f "$theme_dst" 2>/dev/null || true)"
    if [[ "$cur" == "$(readlink -f "$THEME_SRC")" ]]; then
      ok "Theme: ${THEME_NAME} (symlink is correct)"
    else
      warn "Theme: ${THEME_NAME} exists but does not point to $THEME_SRC"
      PLAN_THEME_LINK="yes"
    fi
  else
    warn "Theme: ${THEME_NAME} is not linked"
    PLAN_THEME_LINK="yes"
  fi
}

scan_layout() {
  step "Config deployment check (ready system)"
  PLAN_DIRS=()
  PLAN_DEPLOY=()
  for d in "$HOME/.config" "$HOME/.config/hypr" "$HOME/.config/foot" "$HOME/.config/matugen" "$HOME/.config/mpv" \
           "$ZSH_CUSTOM_DIR/themes" "$ZSH_CUSTOM_DIR/plugins" \
           "$HOME/Pictures/wallpaper" "$HOME/Videos/Recordings"; do
    [[ -d "$d" ]] || PLAN_DIRS+=("$d")
  done

  # foot: local loader config including repo config + local colors.ini
  local foot_cfg="$HOME/.config/foot/foot.ini"
  local foot_colors="$HOME/.config/foot/colors.ini"
  local foot_want
  foot_want=$'include='"$REPO_DIR"$'/config/foot/foot.ini\ninclude='"$HOME"$'/.config/foot/colors.ini\n'
  if [[ -f "$foot_cfg" ]] && [[ "$(cat "$foot_cfg" 2>/dev/null || true)" == "$foot_want" ]]; then
    ok "foot: config loader is set up"
  else
    if [[ -e "$foot_cfg" || -L "$foot_cfg" ]]; then
      PLAN_DEPLOY+=("foot: update $foot_cfg (include repo config, with backup)")
    else
      PLAN_DEPLOY+=("foot: create $foot_cfg (include $REPO_DIR/config/foot/foot.ini and local colors.ini)")
    fi
  fi
  if [[ -f "$foot_colors" && ! -L "$foot_colors" ]]; then
    ok "foot: colors.ini (local, for matugen) is present"
  elif [[ -L "$foot_colors" ]]; then
    PLAN_DEPLOY+=("foot: replace symlink $foot_colors with a regular file (matugen output)")
  else
    PLAN_DEPLOY+=("foot: create empty $foot_colors (matugen output)")
  fi

  # hypr: loader for hyprland.lua, scripts symlink, hyprsunset.conf link, user.lua from example
  local hypr_main="$HOME/.config/hypr/hyprland.lua"
  local hypr_scripts="$HOME/.config/hypr/scripts"
  local hypr_sunset="$HOME/.config/hypr/hyprsunset.conf"
  local hypr_user="$HOME/.config/hypr/user.lua"
  local hypr_loader
  hypr_loader=$'-- kolir loader: delegates to repo config\nlocal repo = "'"$REPO_DIR"$'"\ndofile(repo .. "/config/hypr/hyprland.lua")\n'
  if [[ -f "$hypr_main" && ! -L "$hypr_main" ]] && [[ "$(cat "$hypr_main" 2>/dev/null || true)" == "$hypr_loader" ]]; then
    ok "hypr: hyprland.lua loader is set up"
  else
    PLAN_DEPLOY+=("hypr: set $hypr_main as a loader for $REPO_DIR/config/hypr/hyprland.lua (with backup)")
  fi
  if [[ -L "$hypr_scripts" ]] && [[ "$(readlink -f "$hypr_scripts" 2>/dev/null || true)" == "$(readlink -f "$REPO_DIR/config/hypr/scripts")" ]]; then
    ok "hypr: scripts linked to repo"
  else
    PLAN_DEPLOY+=("hypr: link $hypr_scripts -> $REPO_DIR/config/hypr/scripts (with backup)")
  fi
  if [[ -L "$hypr_sunset" ]] && [[ "$(readlink -f "$hypr_sunset" 2>/dev/null || true)" == "$(readlink -f "$REPO_DIR/config/hypr/hyprsunset.conf")" ]]; then
    ok "hypr: hyprsunset.conf linked to repo"
  elif [[ -f "$hypr_sunset" && ! -L "$hypr_sunset" ]] && have cmp && cmp -s "$hypr_sunset" "$REPO_DIR/config/hypr/hyprsunset.conf" 2>/dev/null; then
    ok "hypr: hyprsunset.conf matches repo"
  else
    PLAN_DEPLOY+=("hypr: link $hypr_sunset to $REPO_DIR/config/hypr/hyprsunset.conf (with backup)")
  fi
  if [[ -f "$hypr_user" ]]; then
    ok "hypr: user.lua (machine-specific) is present"
  else
    PLAN_DEPLOY+=("hypr: create $hypr_user from $REPO_DIR/config/hypr/user.lua.example")
  fi

  # matugen
  local m_cfg="$HOME/.config/matugen/config.toml"
  local m_tpl="$HOME/.config/matugen/templates"
  if [[ -L "$m_cfg" ]] && [[ "$(readlink -f "$m_cfg" 2>/dev/null || true)" == "$(readlink -f "$REPO_DIR/config/matugen/config.toml")" ]]; then
    ok "matugen: config.toml linked to repo"
  else
    PLAN_DEPLOY+=("matugen: symlink $m_cfg -> $REPO_DIR/config/matugen/config.toml (with backup)")
  fi
  if [[ -L "$m_tpl" ]] && [[ "$(readlink -f "$m_tpl" 2>/dev/null || true)" == "$(readlink -f "$REPO_DIR/config/matugen/templates")" ]]; then
    ok "matugen: templates linked to repo"
  else
    PLAN_DEPLOY+=("matugen: symlink $m_tpl -> $REPO_DIR/config/matugen/templates (with backup)")
  fi

  # mpv
  local mpv_cfg="$HOME/.config/mpv/mpv.conf"
  if [[ -L "$mpv_cfg" ]] && [[ "$(readlink -f "$mpv_cfg" 2>/dev/null || true)" == "$(readlink -f "$REPO_DIR/config/mpv/mpv.conf")" ]]; then
    ok "mpv: mpv.conf linked to repo"
  else
    PLAN_DEPLOY+=("mpv: symlink $mpv_cfg -> $REPO_DIR/config/mpv/mpv.conf (with backup)")
  fi

  # zshrc
  local zrc="$HOME/.zshrc"
  if [[ -L "$zrc" ]] && [[ "$(readlink -f "$zrc" 2>/dev/null || true)" == "$(readlink -f "$REPO_DIR/zshrc")" ]]; then
    ok "zshrc: ~/.zshrc linked to repo"
  else
    PLAN_DEPLOY+=("zshrc: symlink $zrc -> $REPO_DIR/zshrc (with backup of existing file)")
  fi

  ok "quickshell: stays in repo (qs -p $REPO_DIR/config/quickshell), no symlink"

  MANUAL=()
  MANUAL+=("hypr (machine-specific): edit ~/.config/hypr/user.lua for monitors/autostart/environment (see $REPO_DIR/config/hypr/user.lua.example).")
  MANUAL+=("Add wallpapers to ~/Pictures/wallpaper (used by hypr scripts).")
}

choose_aur_helper() {
  step "AUR helper"
  local has_paru="no" has_yay="no"
  have paru && has_paru="yes"
  have yay && has_yay="yes"
  info "Found: paru=$has_paru, yay=$has_yay"

  local want_yay="no"
  if ask_yn "Use yay instead of paru? (default: paru)" "N"; then
    want_yay="yes"
  fi

  if [[ "$want_yay" == "yes" ]]; then
    AUR_HELPER="yay"
  else
    AUR_HELPER="paru"
  fi

  if ! have "$AUR_HELPER"; then
    NEED_AUR_BOOTSTRAP="yes"
    warn "Selected AUR helper '$AUR_HELPER' is not installed — it will be bootstrapped after confirmation."
  else
    NEED_AUR_BOOTSTRAP="no"
    ok "Will use AUR helper: $AUR_HELPER"
  fi
}

print_plan() {
  step "ACTION PLAN (nothing changed yet)"
  echo "${BOLD}Install packages (repo, pacman -S --needed):${RESET}"
  if ((${#MISSING_REPO_PKGS[@]}==0)); then
    echo "  - none (all installed)"
  else
    echo "  - ${MISSING_REPO_PKGS[*]}"
  fi

  echo "${BOLD}AUR helper:${RESET} $AUR_HELPER (bootstrap: $NEED_AUR_BOOTSTRAP)"
  echo "${BOLD}Install packages (AUR, via $AUR_HELPER):${RESET}"
  if ((${#MISSING_AUR_PKGS[@]}==0)); then
    echo "  - none"
  else
    echo "  - ${MISSING_AUR_PKGS[*]}"
  fi

  echo "${BOLD}Oh My Zsh:${RESET} $([[ "$PLAN_INSTALL_OMZ" == yes ]] && echo "install ($OMZ_DIR)" || echo "already installed")"
  echo "${BOLD}Oh My Zsh plugins (clone into $ZSH_CUSTOM_DIR/plugins):${RESET}"
  if ((${#PLAN_PLUGINS[@]}==0)); then
    echo "  - no changes"
  else
    for e in "${PLAN_PLUGINS[@]}"; do echo "  - ${e%%|*}"; done
  fi
  echo "${BOLD}Oh My Zsh theme:${RESET} $([[ "$PLAN_THEME_LINK" == yes ]] && echo "create/update symlink $ZSH_CUSTOM_DIR/themes/${THEME_NAME}.zsh-theme -> $THEME_SRC" || echo "no changes")"

  echo "${BOLD}Directories (create if missing):${RESET}"
  if ((${#PLAN_DIRS[@]}==0)); then echo "  - none"; else for d in "${PLAN_DIRS[@]}"; do echo "  - $d"; done; fi

  echo "${BOLD}Config deployment (ready system):${RESET}"
  if ((${#PLAN_DEPLOY[@]}==0)); then
    echo "  - no changes (already configured)"
  else
    for a in "${PLAN_DEPLOY[@]}"; do echo "  - $a"; done
  fi

  echo "${BOLD}Warnings only (will not install):${RESET}"
  if ((${#MISSING_WARN_PKGS[@]}==0)); then echo "  - docker/docker-compose/go present or not required"; else for w in "${MISSING_WARN_PKGS[@]}"; do echo "  - missing: $w"; done; fi

  echo "${BOLD}Manual (machine-specific) steps after install:${RESET}"
  if ((${#MANUAL[@]}==0)); then echo "  - none"; else for m in "${MANUAL[@]}"; do echo "  - $m"; done; fi
}

ensure_sudo() {
  if [[ $EUID -eq 0 ]]; then return 0; fi
  if ! have sudo; then err "sudo not found; required for pacman/bootstrap."; exit 1; fi
  info "Checking sudo..."
  sudo -v
}

install_repo_packages() {
  if ((${#MISSING_REPO_PKGS[@]}==0)); then
    ok "All repo packages are already installed."
    return 0
  fi
  step "Installing packages from official repositories"
  ensure_sudo
  sudo pacman -Syu --needed --noconfirm "${MISSING_REPO_PKGS[@]}"
}

bootstrap_aur_helper() {
  if [[ "$NEED_AUR_BOOTSTRAP" != "yes" ]]; then return 0; fi
  step "Bootstrapping AUR helper: $AUR_HELPER"
  ensure_sudo
  sudo pacman -S --needed --noconfirm base-devel git
  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  if [[ "$AUR_HELPER" == "paru" ]]; then
    info "Cloning and building paru from AUR..."
    git clone https://aur.archlinux.org/paru.git "$tmp/paru"
    (cd "$tmp/paru" && makepkg -si --noconfirm)
  else
    info "Cloning and building yay from AUR..."
    git clone https://aur.archlinux.org/yay.git "$tmp/yay"
    (cd "$tmp/yay" && makepkg -si --noconfirm)
  fi
  if ! have "$AUR_HELPER"; then
    err "Failed to install $AUR_HELPER"; exit 1
  fi
  ok "$AUR_HELPER installed"
}

install_aur_packages() {
  if ((${#MISSING_AUR_PKGS[@]}==0)); then
    ok "No AUR packages to install."
    return 0
  fi
  step "Installing AUR packages via $AUR_HELPER"
  if ! have "$AUR_HELPER"; then
    err "AUR helper '$AUR_HELPER' is not available"; exit 1
  fi
  "$AUR_HELPER" -S --needed --noconfirm "${MISSING_AUR_PKGS[@]}"
}

install_omz() {
  if [[ "$PLAN_INSTALL_OMZ" != "yes" ]]; then return 0; fi
  step "Installing Oh My Zsh"
  if [[ -d "$OMZ_DIR" ]]; then ok "Oh My Zsh already installed"; return 0; fi
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  ok "Oh My Zsh installed"
}

install_plugins() {
  if ((${#PLAN_PLUGINS[@]}==0)); then return 0; fi
  step "Installing Oh My Zsh plugins"
  mkdir -p "$ZSH_CUSTOM_DIR/plugins"
  local entry name url target
  for entry in "${PLAN_PLUGINS[@]}"; do
    name="${entry%%|*}"; url="${entry#*|}"
    target="$ZSH_CUSTOM_DIR/plugins/$name"
    if [[ -d "$target" ]]; then
      ok "Plugin $name already present"
    else
      info "Cloning $name..."
      git clone --depth 1 "$url" "$target"
      ok "Plugin $name installed"
    fi
  done
}

link_theme() {
  step "Linking Oh My Zsh theme ($THEME_NAME)"
  if [[ ! -f "$THEME_SRC" ]]; then
    err "Theme file not found: $THEME_SRC"; exit 1
  fi
  mkdir -p "$ZSH_CUSTOM_DIR/themes"
  local dst="$ZSH_CUSTOM_DIR/themes/${THEME_NAME}.zsh-theme"
  if [[ -e "$dst" || -L "$dst" ]]; then
    local cur=""
    [[ -L "$dst" ]] && cur="$(readlink -f "$dst" 2>/dev/null || true)"
    if [[ "$cur" == "$(readlink -f "$THEME_SRC")" ]]; then
      ok "Theme symlink is already correct"
      return 0
    fi
    local bak="${dst}.bak.$(date +%s)"
    warn "Existing theme backed up to $bak"
    mv "$dst" "$bak"
  fi
  ln -s "$THEME_SRC" "$dst"
  ok "Created symlink: $dst -> $THEME_SRC"
}

backup_path() {
  local p="$1"
  local bak="${p}.bak.$(date +%s)"
  mv "$p" "$bak"
  warn "Backup: $p -> $bak"
}

ensure_symlink() {
  local dst="$1" src="$2"
  mkdir -p "$(dirname "$dst")"
  local src_abs dst_cur
  src_abs="$(readlink -f "$src" 2>/dev/null || echo "$src")"
  if [[ -L "$dst" ]]; then
    dst_cur="$(readlink -f "$dst" 2>/dev/null || true)"
    if [[ "$dst_cur" == "$src_abs" ]]; then
      ok "Symlink OK: $dst"
      return 0
    fi
    backup_path "$dst"
  elif [[ -e "$dst" ]]; then
    backup_path "$dst"
  fi
  ln -s "$src" "$dst"
  ok "Symlink: $dst -> $src"
}

write_file_if_changed() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$path")"
  if [[ -f "$path" && ! -L "$path" ]] && [[ "$(cat "$path")" == "$content" ]]; then
    ok "File up to date: $path"
    return 0
  fi
  if [[ -e "$path" || -L "$path" ]]; then
    backup_path "$path"
  fi
  printf '%s' "$content" > "$path"
  ok "Wrote: $path"
}

deploy_configs() {
  if ((${#PLAN_DEPLOY[@]}==0)); then
    ok "Config deployment: no changes needed."
    return 0
  fi
  step "Deploying configs (ready system)"

  # foot: local loader config + local colors.ini
  local foot_cfg="$HOME/.config/foot/foot.ini"
  local foot_colors="$HOME/.config/foot/colors.ini"
  local foot_want
  foot_want=$'include='"$REPO_DIR"$'/config/foot/foot.ini\ninclude='"$HOME"$'/.config/foot/colors.ini\n'
  write_file_if_changed "$foot_cfg" "$foot_want"
  if [[ -L "$foot_colors" ]]; then
    backup_path "$foot_colors"
  fi
  if [[ ! -f "$foot_colors" ]]; then
    : > "$foot_colors"
    ok "Created: $foot_colors"
  else
    ok "foot colors.ini: $foot_colors"
  fi

  # hypr
  local hypr_main="$HOME/.config/hypr/hyprland.lua"
  local hypr_scripts="$HOME/.config/hypr/scripts"
  local hypr_sunset="$HOME/.config/hypr/hyprsunset.conf"
  local hypr_user="$HOME/.config/hypr/user.lua"
  local hypr_loader
  hypr_loader=$'-- kolir loader: delegates to repo config\nlocal repo = "'"$REPO_DIR"$'"\ndofile(repo .. "/config/hypr/hyprland.lua")\n'
  write_file_if_changed "$hypr_main" "$hypr_loader"
  ensure_symlink "$hypr_scripts" "$REPO_DIR/config/hypr/scripts"
  # hyprsunset.conf: link to repo for readiness
  if [[ -f "$hypr_sunset" && ! -L "$hypr_sunset" ]]; then
    if have cmp && cmp -s "$hypr_sunset" "$REPO_DIR/config/hypr/hyprsunset.conf" 2>/dev/null; then
      backup_path "$hypr_sunset"
    fi
  fi
  ensure_symlink "$hypr_sunset" "$REPO_DIR/config/hypr/hyprsunset.conf"
  if [[ ! -f "$hypr_user" ]]; then
    if [[ -f "$REPO_DIR/config/hypr/user.lua.example" ]]; then
      cp "$REPO_DIR/config/hypr/user.lua.example" "$hypr_user"
      ok "Created machine-specific: $hypr_user (from example)"
    else
      warn "user.lua example not found: $REPO_DIR/config/hypr/user.lua.example"
    fi
  else
    ok "hypr user.lua: $hypr_user"
  fi

  # matugen
  ensure_symlink "$HOME/.config/matugen/config.toml" "$REPO_DIR/config/matugen/config.toml"
  ensure_symlink "$HOME/.config/matugen/templates" "$REPO_DIR/config/matugen/templates"

  # mpv
  ensure_symlink "$HOME/.config/mpv/mpv.conf" "$REPO_DIR/config/mpv/mpv.conf"

  # zshrc
  ensure_symlink "$HOME/.zshrc" "$REPO_DIR/zshrc"
}

create_dirs() {
  if ((${#PLAN_DIRS[@]}==0)); then return 0; fi
  step "Creating directories"
  for d in "${PLAN_DIRS[@]}"; do
    mkdir -p "$d"
    ok "Created: $d"
  done
}

final_report() {
  step "Summary"
  ok "Installation and deployment completed (ready system)."
  if ((${#MISSING_WARN_PKGS[@]})); then
    warn "Missing (not installed automatically): ${MISSING_WARN_PKGS[*]}"
  fi
  echo
  echo "${BOLD}Manual (machine-specific) steps:${RESET}"
  for m in "${MANUAL[@]}"; do
    echo "  - $m"
  done
  echo
  echo "${DIM}Re-running this script is safe (idempotent).${RESET}"
}

bootstrap_repo() {
  step "Repository bootstrap"
  echo "${BOLD}PLAN (bootstrap):${RESET}"
  if [[ -d "$REPO_DIR/.git" ]]; then
    echo "  - Repository already exists: $REPO_DIR"
    echo "  - Update: git pull --ff-only (if possible)"
  else
    echo "  - Clone $KOLIR_REPO_URL -> $REPO_DIR"
    [[ -n "$KOLIR_BRANCH" ]] && echo "  - Branch: $KOLIR_BRANCH"
  fi
  echo "  - Then run the installer from $REPO_DIR/install.sh (it will show the full dependency/deploy plan and ask for confirmation)"

  if ! have git; then
    echo "  - git is missing: will be installed via 'sudo pacman -S --needed git'"
  fi
  echo
  if ! ask_yn "${BOLD}Proceed with repository bootstrap?${RESET}" "N"; then
    warn "Cancelled by user. No changes made."
    exit 0
  fi

  if ! have git; then
    ensure_sudo
    sudo pacman -S --needed --noconfirm git
  fi

  mkdir -p "$(dirname "$REPO_DIR")"
  if [[ -d "$REPO_DIR/.git" ]]; then
    info "Updating repository in $REPO_DIR..."
    if ! git -C "$REPO_DIR" pull --ff-only; then
      warn "Fast-forward pull failed. Continuing with the current repository state."
    fi
  elif [[ -e "$REPO_DIR" ]] && [[ -n "$(ls -A "$REPO_DIR" 2>/dev/null || true)" ]]; then
    err "Directory $REPO_DIR exists and is not a git repository. Move it or set a different path via KOLIR_DIR."
    exit 1
  else
    info "Cloning $KOLIR_REPO_URL into $REPO_DIR..."
    if [[ -n "$KOLIR_BRANCH" ]]; then
      git clone --branch "$KOLIR_BRANCH" "$KOLIR_REPO_URL" "$REPO_DIR"
    else
      git clone "$KOLIR_REPO_URL" "$REPO_DIR"
    fi
  fi

  if [[ ! -x "$REPO_DIR/install.sh" ]]; then
    chmod +x "$REPO_DIR/install.sh" || true
  fi
  ok "Repository ready: $REPO_DIR"
  echo
  exec bash "$REPO_DIR/install.sh" --from-bootstrap "$@"
}

main() {
  preflight
  if [[ "$BOOTSTRAP_MODE" == "yes" ]]; then
    bootstrap_repo "$@"
  fi

  scan_packages
  scan_omz
  scan_layout
  choose_aur_helper
  print_plan

  echo
  if ! ask_yn "${BOLD}Proceed with the plan?${RESET}" "N"; then
    warn "Cancelled by user. No changes made."
    exit 0
  fi

  install_repo_packages
  bootstrap_aur_helper
  install_aur_packages
  install_omz
  install_plugins
  link_theme
  create_dirs
  deploy_configs
  final_report
}

main "$@"
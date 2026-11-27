#!/usr/bin/env bash
# =============================================================================
#  CachyOS (No Desktop) -> Umbriel + Noctalia + Luciole + Noctalia Greeter
# =============================================================================
#  Run as your normal user (NOT root) from the TTY after first boot:
#
#     curl -LO https://raw.githubusercontent.com/lmaule/cachy-umbriel-noctalia/main/install.sh
#     bash install.sh
#
#  The script is safe to re-run: packages use --needed and existing configs
#  are backed up rather than overwritten.
# =============================================================================

set -Eeuo pipefail

# ---------------------------------------------------------------------------
# Settings you may want to change
# ---------------------------------------------------------------------------
TERMINAL_PKG="alacritty"      # Preinstalled by CachyOS; bound to Super+Return
# Fonts, PipeWire, polkit, accountsservice, git and alacritty already come with
# every CachyOS install (cachyos-calamares netinstall "Base-devel + Common").
# These are the bits the no-desktop install does NOT include:
EXTRA_PKGS=(
  xdg-desktop-portal xdg-desktop-portal-gtk   # file pickers, screen sharing
  xorg-xwayland                               # run X11 apps
)
ENABLE_GREETER=true           # set to false to keep booting into the TTY

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
c_blue=$'\e[1;34m'; c_green=$'\e[1;32m'; c_yellow=$'\e[1;33m'; c_red=$'\e[1;31m'; c_off=$'\e[0m'
step() { printf '\n%s==>%s %s\n' "$c_blue" "$c_off" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$c_green" "$c_off" "$*"; }
warn() { printf '%s  !%s %s\n' "$c_yellow" "$c_off" "$*"; }
die()  { printf '%s  ✗ %s%s\n' "$c_red" "$*" "$c_off" >&2; exit 1; }

LOG="$HOME/noctalia-install-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG") 2>&1
trap 'die "Failed on line $LINENO: $BASH_COMMAND  (full log: $LOG)"' ERR

backup() {  # backup <file> [sudo]
  local f="$1" s="${2:-}"
  if [[ -e "$f" ]]; then
    $s cp -a "$f" "$f.bak.$(date +%Y%m%d-%H%M%S)"
    ok "Backed up $f"
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Step 0 – Pre-flight checks
# ---------------------------------------------------------------------------
step "Step 0: Pre-flight checks"

[[ $EUID -ne 0 ]] || die "Run this as your normal user, not root (AUR packages can't be built as root)."
command -v pacman >/dev/null || die "pacman not found – this script is for CachyOS/Arch."
grep -qiE '^ID(_LIKE)?=.*(cachyos|arch)' /etc/os-release || warn "This doesn't look like CachyOS/Arch – continuing anyway."
command -v sudo >/dev/null || die "sudo is not installed."

if ! curl -fsS --max-time 10 https://archlinux.org >/dev/null; then
  die "No internet connection. On a TTY try: nmtui  (or: iwctl for Wi-Fi)"
fi
ok "Internet is reachable"

echo
echo "This will install: umbriel-git, noctalia, luciole-git, noctalia-greeter (+ greetd)"
echo "Log file: $LOG"
read -rp "Continue? [Y/n] " reply
[[ "${reply:-Y}" =~ ^[Yy]$ ]] || exit 0

# Ask for the sudo password once, then keep the ticket alive while we work.
sudo -v
( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) &
SUDO_KEEPALIVE=$!
trap 'kill $SUDO_KEEPALIVE 2>/dev/null || true' EXIT

# ---------------------------------------------------------------------------
# Step 1 – Update the system
# ---------------------------------------------------------------------------
step "Step 1: Full system update"
sudo pacman -Syu --noconfirm
ok "System up to date"

# ---------------------------------------------------------------------------
# Step 2 – Build tools and desktop basics
# ---------------------------------------------------------------------------
step "Step 2: Installing build tools and the few missing desktop basics"
sudo pacman -S --needed --noconfirm base-devel "${EXTRA_PKGS[@]}"
ok "Base packages installed"

# ---------------------------------------------------------------------------
# Step 3 – AUR helper (paru preferred, yay accepted)
# ---------------------------------------------------------------------------
step "Step 3: Making sure an AUR helper is available"
if command -v paru >/dev/null; then
  AUR=(paru -S --needed --noconfirm --skipreview)
elif command -v yay >/dev/null; then
  AUR=(yay -S --needed --noconfirm --answerdiff None --answerclean None)
else
  # CachyOS ships paru in its own repo; fall back to building from the AUR.
  if sudo pacman -S --needed --noconfirm paru; then
    ok "Installed paru from the CachyOS repo"
  else
    warn "paru not in repos – building paru-bin from the AUR"
    tmp=$(mktemp -d)
    git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
    (cd "$tmp/paru-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
  fi
  AUR=(paru -S --needed --noconfirm --skipreview)
fi
ok "Using ${AUR[0]}"

# ---------------------------------------------------------------------------
# Step 4 – Noctalia (repo package)
# ---------------------------------------------------------------------------
step "Step 4: Installing Noctalia shell"
sudo pacman -S --needed --noconfirm noctalia
ok "Noctalia installed"

# ---------------------------------------------------------------------------
# Step 5 – Umbriel and Luciole (AUR, built from source – takes a while)
# ---------------------------------------------------------------------------
step "Step 5: Building Umbriel and Luciole from the AUR (this can take several minutes)"
"${AUR[@]}" umbriel-git luciole-git
command -v umbriel >/dev/null || die "umbriel binary not found after install."
ok "Umbriel and Luciole installed"

# ---------------------------------------------------------------------------
# Step 6 – Configure Umbriel to run Noctalia
# ---------------------------------------------------------------------------
step "Step 6: Writing Umbriel config"

UCONF="${XDG_CONFIG_HOME:-$HOME/.config}/umbriel"
mkdir -p "$UCONF"

# 6a. Copy the packaged example config as an editable base (only once).
EXAMPLE=""
for f in /usr/share/umbriel/config.toml /usr/local/share/umbriel/config.toml; do
  if [[ -f "$f" ]]; then EXAMPLE="$f"; break; fi
done
[[ -n "$EXAMPLE" ]] || die "Couldn't find Umbriel's example config.toml"

if [[ ! -f "$UCONF/base.toml" ]]; then
  cp "$EXAMPLE" "$UCONF/base.toml"
  ok "Copied example config to $UCONF/base.toml"
else
  ok "Keeping existing $UCONF/base.toml"
fi

# 6b. Noctalia integration lives in its own file (always refreshed).
cat > "$UCONF/noctalia.toml" <<'EOF'
# Managed by install.sh – Noctalia integration for Umbriel.
# Put personal overrides in config.toml instead; this file may be regenerated.

[general]
autostart = ["noctalia"]

[keybinds]
"Mod+Return"            = "spawn @TERMINAL@"
"Mod+Space"           = "spawn noctalia msg panel-toggle launcher"
"Mod+S"                 = "spawn noctalia msg panel-toggle control-center"
"Mod+Comma"             = "spawn noctalia msg settings-toggle"
"Alt+Tab"               = "spawn noctalia msg window-switcher hold"
"Alt+Shift+Tab"         = "spawn noctalia msg window-switcher hold reverse"
"Mod+Shift+A"           = "spawn noctalia msg screenshot-annotate"
"Mod+E"                 = "spawn luciole"
"XF86AudioRaiseVolume"  = "spawn noctalia msg volume-up"
"XF86AudioLowerVolume"  = "spawn noctalia msg volume-down"
"XF86AudioMute"         = "spawn noctalia msg volume-mute"
"XF86MonBrightnessUp"   = "spawn noctalia msg brightness-up"
"XF86MonBrightnessDown" = "spawn noctalia msg brightness-down"

# Float Noctalia's settings window
[[window_rule]]
match.app_id = "^dev.noctalia.Noctalia$"
default_floating = true
default_size = [1020, 900]

# Blur behind Noctalia's bar, panels, dock, notifications and OSD
[[layer_rule]]
match.namespace = "^noctalia-(bar-[^\"]+|notification|dock|panel|attached-panel|osd)$"
blur = true
blur_ignore_alpha = 0.6
blur_optimized = false
EOF
sed -i "s/@TERMINAL@/$TERMINAL_PKG/" "$UCONF/noctalia.toml"
ok "Wrote $UCONF/noctalia.toml"

# 6c. Main config: includes base, then Noctalia, then your own overrides below.
if [[ ! -f "$UCONF/config.toml" ]] || ! grep -q 'noctalia.toml' "$UCONF/config.toml"; then
  backup "$UCONF/config.toml"
  {
    echo '# Umbriel main config (created by install.sh)'
    echo '# Load order: base.toml -> noctalia.toml -> this file (last one wins).'
    echo
    echo '[include]'
    echo 'files = ["base.toml", "noctalia.toml"]'
    echo
    # Umbriel requires [drm] in the main file if an include defines it.
    if grep -q '^\[drm\]' "$UCONF/base.toml"; then echo '[drm]'; echo; fi
    echo '# --- Your overrides go below this line ---'
  } > "$UCONF/config.toml"
  ok "Wrote $UCONF/config.toml"
else
  ok "config.toml already includes noctalia.toml – left untouched"
fi

if umbriel config validate >/dev/null 2>&1; then
  ok "umbriel config validate: OK"
else
  warn "umbriel config validate reported problems – run 'umbriel config validate' to see them."
fi

# ---------------------------------------------------------------------------
# Step 7 – greetd + Noctalia Greeter
# ---------------------------------------------------------------------------
step "Step 7: Installing greetd and Noctalia Greeter"
sudo pacman -S --needed --noconfirm greetd noctalia-greeter
GREETER_SESSION=$(command -v noctalia-greeter-session) || die "noctalia-greeter-session not found."
ok "Greeter installed ($GREETER_SESSION)"

# Run the packaged setup script if one ships (creates /var/lib/noctalia-greeter).
setup_script=$(pacman -Qlq noctalia-greeter | grep -iE 'setup[^/]*$' | grep -v '/$' | head -n1 || true)
if [[ -n "$setup_script" && -x "$setup_script" ]]; then
  sudo "$setup_script" && ok "Ran $setup_script"
else
  sudo install -d -o greeter -g greeter -m 0755 /var/lib/noctalia-greeter
  ok "Created /var/lib/noctalia-greeter"
fi

# Pre-select your user and the Umbriel session. The greeter matches sessions by
# the desktop entry's Name= field (what the picker shows), not the file name.
LOGIN_USER="$(id -un)"
SESSION_NAME=""
for d in /usr/share/wayland-sessions/*.desktop /usr/local/share/wayland-sessions/*.desktop; do
  [[ -f "$d" ]] || continue
  if [[ "$(basename "$d")" == *umbriel* ]]; then
    SESSION_NAME=$(grep -m1 '^Name=' "$d" | cut -d= -f2-)
    break
  fi
done

GREETER_ARGS="--user $LOGIN_USER"
if [[ -z "$SESSION_NAME" ]]; then
  warn "No Umbriel session file found – the greeter will show the session picker."
elif [[ "$SESSION_NAME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  GREETER_ARGS="--session $SESSION_NAME $GREETER_ARGS"
else
  # Names with spaces/punctuation go in greeter.toml to avoid shell quoting issues.
  sudo tee /var/lib/noctalia-greeter/greeter.toml >/dev/null <<EOF
[session]
default = "$SESSION_NAME"
EOF
  sudo chown greeter:greeter /var/lib/noctalia-greeter/greeter.toml
fi
ok "Login screen will pre-select user '$LOGIN_USER' and session '${SESSION_NAME:-<picker>}'"

backup /etc/greetd/config.toml sudo
sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 1

[default_session]
command = "$GREETER_SESSION -- $GREETER_ARGS"
user = "greeter"
EOF
ok "Wrote /etc/greetd/config.toml"

if [[ "$ENABLE_GREETER" == true ]]; then
  # Disable any other display manager so it doesn't fight greetd.
  current_dm=$(systemctl show -p Id --value display-manager.service 2>/dev/null || true)
  if [[ -n "$current_dm" && "$current_dm" != "greetd.service" && "$current_dm" != "display-manager.service" ]]; then
    sudo systemctl disable "$current_dm" && warn "Disabled $current_dm"
  fi
  sudo systemctl enable greetd.service
  sudo systemctl enable accounts-daemon.service 2>/dev/null || true
  ok "greetd enabled – it will start on next boot"
else
  warn "Greeter not enabled (ENABLE_GREETER=false). Start the desktop with: start-umbriel"
fi

# ---------------------------------------------------------------------------
# Step 8 – Done
# ---------------------------------------------------------------------------
step "Step 8: All done!"
cat <<EOF

  Installed:  Umbriel · Noctalia · Luciole · Noctalia Greeter
  Configs:    $UCONF/{config,base,noctalia}.toml
              /etc/greetd/config.toml
  Log:        $LOG

  Keys:  Super+Return  terminal ($TERMINAL_PKG)
         Super+Space   launcher        Super+S      control centre
         Super+E       Luciole         Super+,      Noctalia settings

  Tip: once logged in, Noctalia → Settings → Security → Noctalia Greeter
       → "Sync Now" makes the login screen match your desktop theme.

  If the greeter ever fails, switch to another TTY (Ctrl+Alt+F2),
  log in, and run:  sudo systemctl disable greetd

EOF

read -rp "Reboot now? [y/N] " reply
if [[ "${reply:-N}" =~ ^[Yy]$ ]]; then sudo reboot; fi

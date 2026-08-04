#!/usr/bin/env bash
set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Dry-run flag (set by --dry-run argument) ─────────────────────────────────
DRY_RUN=false

# ─── Helpers ─────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }
dryrun()  { echo -e "${CYAN}[DRY-RUN]${RESET} would run: $*"; }

step() {
  echo ""
  echo -e "${BOLD}═══ $* ═══${RESET}"
}

# run CMD [ARGS...] — executes the command normally, or prints it in dry-run mode
run() {
  if $DRY_RUN; then
    dryrun "$*"
  else
    "$@"
  fi
}

# write_file PATH CONTENT — writes a file, or shows a preview in dry-run mode
write_file() {
  local path="$1"
  local content="$2"
  if $DRY_RUN; then
    dryrun "write to $path:"
    echo "$content" | sed 's/^/             | /'
  else
    echo "$content" > "$path"
  fi
}

# append_file PATH CONTENT — appends to a file, or shows a preview in dry-run mode
append_file() {
  local path="$1"
  local content="$2"
  if $DRY_RUN; then
    dryrun "append to $path:"
    echo "$content" | sed 's/^/             | /'
  else
    echo "$content" >> "$path"
  fi
}

# ─── Guards ──────────────────────────────────────────────────────────────────
check_root() {
  if [[ $EUID -eq 0 ]]; then
    die "Do not run this script as root. Run as your normal user — sudo will be called as needed."
  fi
}

check_os() {
  if $DRY_RUN; then
    if [[ ! -f /etc/debian_version ]]; then
      warn "[DRY-RUN] Not on a Debian/Ubuntu system — checks will be simulated."
    else
      info "Detected Debian/Ubuntu system."
    fi
    return
  fi
  if [[ ! -f /etc/debian_version ]]; then
    die "This script requires a Debian/Ubuntu-based system."
  fi
  info "Detected Debian/Ubuntu system."
}

check_internet() {
  info "Checking internet connectivity..."
  if $DRY_RUN; then
    dryrun "curl -fsS --max-time 5 https://github.com  (connectivity check skipped)"
    return
  fi
  if ! curl -fsS --max-time 5 https://github.com > /dev/null 2>&1; then
    die "No internet connection. Please connect and re-run."
  fi
  success "Internet connection OK."
}

require_cmd() {
  if $DRY_RUN; then
    if ! command -v "$1" &>/dev/null; then
      warn "Command '$1' not currently installed — would be available after package install."
    fi
    return
  fi
  command -v "$1" &>/dev/null || die "Required command '$1' not found after install — check your PATH."
}

# ─── Step 1: Packages ────────────────────────────────────────────────────────
install_packages() {
  step "Step 1 — Installing APT packages"

  local packages=(
    zsh
    net-tools
    fonts-font-awesome
    lm-sensors
    hardinfo
    glances
    apt-transport-https
    curl
    git
  )

  if $DRY_RUN; then
    dryrun "sudo apt update -qq"
    dryrun "sudo apt install -y ${packages[*]}"
    return
  fi

  info "Running apt update..."
  sudo apt update -qq || die "apt update failed. Check your sources.list or network."

  info "Installing: ${packages[*]}"
  if ! sudo apt install -y "${packages[@]}"; then
    error "One or more packages failed to install."
    error "Try running manually: sudo apt install -y ${packages[*]}"
    die "Package installation failed."
  fi

  success "All packages installed."
}

# ─── Step 2: Default Shell ───────────────────────────────────────────────────
set_default_shell() {
  step "Step 2 — Setting Zsh as default shell"

  local zsh_path="/usr/bin/zsh"
  if command -v zsh &>/dev/null; then
    zsh_path=$(which zsh)
  fi

  if ! $DRY_RUN && [[ "$SHELL" == "$zsh_path" ]]; then
    warn "Zsh is already your default shell. Skipping."
    return
  fi

  if $DRY_RUN; then
    dryrun "chsh -s $zsh_path  (change default shell for user '$USER')"
    return
  fi

  info "Changing default shell to $zsh_path for user '$USER'..."
  if ! chsh -s "$zsh_path"; then
    error "chsh failed. You may need to add $zsh_path to /etc/shells first:"
    error "  echo '$zsh_path' | sudo tee -a /etc/shells"
    die "Failed to set default shell."
  fi

  success "Default shell set to $zsh_path. Log out and back in for it to take effect."
}

# ─── Step 3: Oh My Zsh ───────────────────────────────────────────────────────
install_omz() {
  step "Step 3 — Installing Oh My Zsh"

  if ! $DRY_RUN && [[ -d "$HOME/.oh-my-zsh" ]]; then
    warn "Oh My Zsh is already installed at ~/.oh-my-zsh. Skipping."
    return
  fi

  if $DRY_RUN; then
    dryrun "curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | RUNZSH=no CHSH=no sh"
    return
  fi

  require_cmd curl
  info "Downloading and running Oh My Zsh installer..."

  # RUNZSH=no prevents the installer from immediately switching to zsh mid-script
  # CHSH=no because we already handled it above
  if ! RUNZSH=no CHSH=no \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"; then
    die "Oh My Zsh installation failed. Check the output above for details."
  fi

  success "Oh My Zsh installed."
}

# ─── Step 4: MesloLGS Nerd Fonts ─────────────────────────────────────────────
install_fonts() {
  step "Step 4 — Installing MesloLGS NF fonts"

  local font_dir="$HOME/.local/share/fonts"

  local font_names=(
    "MesloLGS NF Regular.ttf"
    "MesloLGS NF Bold.ttf"
    "MesloLGS NF Italic.ttf"
    "MesloLGS NF Bold Italic.ttf"
  )
  local font_urls=(
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf"
    "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf"
  )

  if $DRY_RUN; then
    dryrun "mkdir -p $font_dir"
    for i in "${!font_names[@]}"; do
      dryrun "curl -fLo \"$font_dir/${font_names[$i]}\" ${font_urls[$i]}"
    done
    dryrun "fc-cache -fv"
    return
  fi

  mkdir -p "$font_dir"

  local failed=0
  for i in "${!font_names[@]}"; do
    local name="${font_names[$i]}"
    local dest="$font_dir/$name"
    if [[ -f "$dest" ]]; then
      warn "Font already exists, skipping: $name"
      continue
    fi
    info "Downloading: $name"
    if ! curl -fLo "$dest" "${font_urls[$i]}"; then
      error "Failed to download: $name"
      failed=$(( failed + 1 ))
    fi
  done

  if [[ $failed -gt 0 ]]; then
    die "$failed font(s) failed to download. Check your internet connection and retry."
  fi

  info "Refreshing font cache..."
  fc-cache -fv > /dev/null 2>&1 || warn "fc-cache failed — fonts may not appear until you log out."

  success "Fonts installed to $font_dir"
  warn "Remember to set 'MesloLGS NF' as your terminal emulator's font manually."
}

# ─── Step 5: Powerlevel10k ────────────────────────────────────────────────────
install_p10k() {
  step "Step 5 — Installing Powerlevel10k"

  local p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
  local zshrc="$HOME/.zshrc"

  if $DRY_RUN; then
    if [[ -d "$p10k_dir" ]]; then
      warn "Powerlevel10k already installed at $p10k_dir — would skip clone."
    else
      dryrun "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $p10k_dir"
    fi
    if [[ -f "$zshrc" ]] && grep -q 'ZSH_THEME="powerlevel10k/powerlevel10k"' "$zshrc"; then
      warn "ZSH_THEME already set in ~/.zshrc — would skip."
    else
      dryrun "sed -i 's|^ZSH_THEME=.*|ZSH_THEME=\"powerlevel10k/powerlevel10k\"|' ~/.zshrc"
    fi
    return
  fi

  if [[ -d "$p10k_dir" ]]; then
    warn "Powerlevel10k already installed at $p10k_dir. Skipping clone."
  else
    require_cmd git
    info "Cloning Powerlevel10k..."
    if ! git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"; then
      die "Failed to clone Powerlevel10k. Check your internet connection."
    fi
    success "Powerlevel10k cloned."
  fi

  if [[ ! -f "$zshrc" ]]; then
    warn "~/.zshrc not found. Creating a basic one."
    printf 'export ZSH="$HOME/.oh-my-zsh"\nsource $ZSH/oh-my-zsh.sh\n' > "$zshrc"
  fi

  if grep -q 'ZSH_THEME="powerlevel10k/powerlevel10k"' "$zshrc"; then
    warn "Powerlevel10k theme already set in ~/.zshrc. Skipping."
  else
    info "Setting ZSH_THEME in ~/.zshrc..."
    if grep -q '^ZSH_THEME=' "$zshrc"; then
      sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$zshrc"
    else
      echo 'ZSH_THEME="powerlevel10k/powerlevel10k"' >> "$zshrc"
    fi
    success "ZSH_THEME set to powerlevel10k/powerlevel10k."
  fi
}

# ─── Step 6: Plugins ─────────────────────────────────────────────────────────
install_plugins() {
  step "Step 6 — Installing Zsh plugins"

  local custom_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"

  if $DRY_RUN; then
    if [[ -d "$custom_dir/zsh-autosuggestions" ]]; then
      warn "zsh-autosuggestions already installed — would skip."
    else
      dryrun "git clone https://github.com/zsh-users/zsh-autosuggestions $custom_dir/zsh-autosuggestions"
    fi
    if [[ -d "$custom_dir/zsh-syntax-highlighting" ]]; then
      warn "zsh-syntax-highlighting already installed — would skip."
    else
      dryrun "git clone https://github.com/zsh-users/zsh-syntax-highlighting $custom_dir/zsh-syntax-highlighting"
    fi
    return
  fi

  local autosug_dir="$custom_dir/zsh-autosuggestions"
  if [[ -d "$autosug_dir" ]]; then
    warn "zsh-autosuggestions already installed. Skipping."
  else
    info "Cloning zsh-autosuggestions..."
    if ! git clone https://github.com/zsh-users/zsh-autosuggestions "$autosug_dir"; then
      die "Failed to clone zsh-autosuggestions."
    fi
    success "zsh-autosuggestions installed."
  fi

  local syntax_dir="$custom_dir/zsh-syntax-highlighting"
  if [[ -d "$syntax_dir" ]]; then
    warn "zsh-syntax-highlighting already installed. Skipping."
  else
    info "Cloning zsh-syntax-highlighting..."
    if ! git clone https://github.com/zsh-users/zsh-syntax-highlighting "$syntax_dir"; then
      die "Failed to clone zsh-syntax-highlighting."
    fi
    success "zsh-syntax-highlighting installed."
  fi
}

# ─── Step 7: Configure .zshrc ─────────────────────────────────────────────────
configure_zshrc() {
  step "Step 7 — Configuring ~/.zshrc"

  local zshrc="$HOME/.zshrc"

  local instant_prompt='# Enable Powerlevel10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi'

  if $DRY_RUN; then
    if [[ -f "$zshrc" ]] && grep -q 'zsh-autosuggestions' "$zshrc" && grep -q 'zsh-syntax-highlighting' "$zshrc"; then
      warn "plugins=() already configured in ~/.zshrc — would skip."
    else
      dryrun "perl -i -0pe 's/^plugins=\\(.*?\\)/plugins=(\\n  git\\n  zsh-autosuggestions\\n  zsh-syntax-highlighting\\n)/ms' ~/.zshrc"
    fi
    if [[ -f "$zshrc" ]] && grep -q 'p10k-instant-prompt' "$zshrc"; then
      warn "p10k instant prompt block already present — would skip."
    else
      dryrun "prepend to ~/.zshrc:"
      echo "$instant_prompt" | sed 's/^/             | /'
    fi
    if [[ -f "$zshrc" ]] && grep -q 'source ~/.p10k.zsh' "$zshrc"; then
      warn "p10k source line already present — would skip."
    else
      dryrun "append to ~/.zshrc: [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh"
    fi
    return
  fi

  if grep -q 'zsh-autosuggestions' "$zshrc" && grep -q 'zsh-syntax-highlighting' "$zshrc"; then
    warn "Plugins already configured in ~/.zshrc. Skipping."
  else
    info "Updating plugins=() in ~/.zshrc..."
    if ! perl -i -0pe \
      's/^plugins=\(.*?\)/plugins=(\n  git\n  zsh-autosuggestions\n  zsh-syntax-highlighting\n)/ms' \
      "$zshrc"; then
      warn "Could not auto-update plugins line. Add this to ~/.zshrc manually:"
      warn "  plugins=(git zsh-autosuggestions zsh-syntax-highlighting)"
    else
      success "plugins=() updated."
    fi
  fi

  if grep -q 'p10k-instant-prompt' "$zshrc"; then
    warn "p10k instant prompt block already present in ~/.zshrc. Skipping."
  else
    info "Prepending p10k instant prompt block to ~/.zshrc..."
    local tmp
    tmp=$(mktemp)
    { echo "$instant_prompt"; echo ""; cat "$zshrc"; } > "$tmp"
    mv "$tmp" "$zshrc"
    success "p10k instant prompt block added."
  fi

  if grep -q 'source ~/.p10k.zsh' "$zshrc"; then
    warn "p10k source line already present in ~/.zshrc. Skipping."
  else
    printf '\n# Load Powerlevel10k config (run "p10k configure" to generate)\n[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh\n' >> "$zshrc"
    success "p10k source line added to ~/.zshrc."
  fi
}

# ─── Summary ──────────────────────────────────────────────────────────────────
print_summary() {
  echo ""
  if $DRY_RUN; then
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}║   Dry-run complete — no changes were made.   ║${RESET}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "Run ${BOLD}without${RESET} --dry-run to apply all changes:"
    echo "  bash setup-zsh.sh"
  else
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════╗${RESET}"
    echo -e "${GREEN}${BOLD}║         Setup complete!                      ║${RESET}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════╝${RESET}"
    echo ""
    echo -e "${BOLD}Next steps:${RESET}"
    echo "  1. Set your terminal font to 'MesloLGS NF'"
    echo "     GNOME Terminal : Preferences → Profile → Text → Custom font"
    echo "     Konsole        : Settings → Edit Profile → Appearance → Font"
    echo "     VS Code        : settings.json → \"terminal.integrated.fontFamily\": \"MesloLGS NF\""
    echo ""
    echo "  2. Log out and back in (or open a new terminal) to start using Zsh"
    echo ""
    echo "  3. The Powerlevel10k wizard will launch automatically."
    echo "     To re-run it later: p10k configure"
    echo ""
    echo -e "${YELLOW}Tip:${RESET} Press → (right arrow) to accept autosuggestions as you type."
  fi
}

# ─── Usage ────────────────────────────────────────────────────────────────────
usage() {
  echo "Usage: $0 [--dry-run]"
  echo ""
  echo "  --dry-run   Show what would be done without making any changes."
  echo "  --help      Show this help message."
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
  # Parse arguments
  for arg in "$@"; do
    case "$arg" in
      --dry-run) DRY_RUN=true ;;
      --help|-h) usage; exit 0 ;;
      *) die "Unknown argument: $arg. Use --dry-run or --help." ;;
    esac
  done

  echo -e "${BOLD}"
  echo "  ╔═══════════════════════════════════════════╗"
  echo "  ║   Ubuntu/Debian Zsh + OMZ + p10k Setup   ║"
  if $DRY_RUN; then
  echo "  ║           *** DRY-RUN MODE ***            ║"
  fi
  echo "  ╚═══════════════════════════════════════════╝"
  echo -e "${RESET}"

  if $DRY_RUN; then
    warn "Dry-run mode enabled — no files will be created, modified, or downloaded."
    echo ""
  fi

  check_root
  check_os
  check_internet

  install_packages
  set_default_shell
  install_omz
  install_fonts
  install_p10k
  install_plugins
  configure_zshrc

  print_summary
}

main "$@"

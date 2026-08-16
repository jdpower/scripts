# Ubuntu / Debian Terminal Setup Guide

## 1. Install Required Packages

```bash
sudo apt update && sudo apt install -y \
  zsh \
  net-tools \
  fonts-font-awesome \
  lm-sensors \
  hardinfo \
  glances \
  apt-transport-https \
  curl \
  git
```

---

## 2. Set Zsh as Default Shell

```bash
chsh -s $(which zsh)
```

Log out and back in (or reboot) for the change to take effect. Verify with:

```bash
echo $SHELL
# Expected: /usr/bin/zsh
```

---

## 3. Install Oh My Zsh

```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

This creates `~/.zshrc` and sets up the `~/.oh-my-zsh/` directory.

---

## 4. Themes Overview

Oh My Zsh ships with many built-in themes. View all available themes:

```bash
ls ~/.oh-my-zsh/themes/
```

Or browse the [theme gallery](https://github.com/ohmyzsh/ohmyzsh/wiki/Themes).

### Popular Built-in Themes

| Theme | Description |
| ------- | ------------- |
| `robbyrussell` | Default. Clean, minimal prompt with git status |
| `agnoster` | Powerline-style, shows git branch and status |
| `bureau` | Two-line prompt with user, dir, git info |
| `clean` | Minimal, shows git branch inline |
| `dst` | Compact with timestamp |
| `fino` | Colored prompt with git info |
| `gallois` | Shows git status with symbols |
| `jonathan` | Multiline with time, user, and path |
| `juanghurtado` | Clean two-line with git info |
| `ys` | Clean, two-line, shows full path and git |

### Change Theme

Edit `~/.zshrc` and set:

```bash
ZSH_THEME="agnoster"
```

Then reload:

```bash
source ~/.zshrc
```

---

## 5. Install Powerlevel10k (Recommended Theme)

Powerlevel10k is a fast, highly customizable Zsh theme with an interactive setup wizard.

### Step 1 — Install Nerd Fonts (required for icons)

Download and install **MesloLGS NF** (recommended for p10k):

```bash
mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts

curl -fLo "MesloLGS NF Regular.ttf"    https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf
curl -fLo "MesloLGS NF Bold.ttf"       https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold.ttf
curl -fLo "MesloLGS NF Italic.ttf"     https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Italic.ttf
curl -fLo "MesloLGS NF Bold Italic.ttf" https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Bold%20Italic.ttf

fc-cache -fv
```

Then set **MesloLGS NF** as your terminal emulator's font:

- **GNOME Terminal**: Preferences → Profile → Text → Custom font
- **Konsole**: Settings → Edit Current Profile → Appearance → Font
- **Tilix**: Preferences → Profile → General → Custom Font
- **VS Code**: add to `settings.json`: `"terminal.integrated.fontFamily": "MesloLGS NF"`

### Step 2 — Clone Powerlevel10k

```bash
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
  ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
```

### Step 3 — Set the Theme

Edit `~/.zshrc`:

```bash
ZSH_THEME="powerlevel10k/powerlevel10k"
```

Reload the shell:

```bash
source ~/.zshrc
```

### Step 4 — Run the Configuration Wizard

The wizard launches automatically on first load. To re-run it at any time:

```bash
p10k configure
```

**Wizard walkthrough:**

1. **Diamond / Lock / Debian logo checks** — confirms your font renders icons correctly
2. **Prompt Style** — choose from Lean, Classic, Rainbow, or Pure
3. **Character Set** — Unicode (recommended) or ASCII fallback
4. **Prompt Color** — Dark, Light, or custom
5. **Show current time** — No / 12-hour / 24-hour
6. **Prompt Separators** — Angled, Vertical, Slanted, or Round
7. **Prompt Heads / Tails** — various end-cap styles
8. **Prompt Height** — One or Two lines
9. **Prompt Spacing** — Compact or Loose
10. **Icons** — Few or Many
11. **Prompt Flow** — Concise or Fluent
12. **Enable Transient Prompt** — cleans up previous prompts in history
13. **Instant Prompt** — Verbose (recommended), Quiet, or Off

Your choices are saved to `~/.p10k.zsh`. Edit it directly for fine-grained tweaks.

### Re-configuring Later

```bash
p10k configure        # re-run the full wizard
nano ~/.p10k.zsh      # edit configuration directly
```

---

## 6. Install Plugins

### zsh-autosuggestions

Suggests commands as you type based on history.

```bash
git clone https://github.com/zsh-users/zsh-autosuggestions \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
```

### zsh-syntax-highlighting (optional but recommended)

Highlights valid commands green, invalid ones red.

```bash
git clone https://github.com/zsh-users/zsh-syntax-highlighting \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
```

### Enable Plugins

Edit `~/.zshrc` and update the plugins line:

```bash
plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
)
```

> **Note:** `zsh-syntax-highlighting` must always be **last** in the list.

Reload:

```bash
source ~/.zshrc
```

---

## 7. Plugin Usage

### git plugin

Built into Oh My Zsh. Provides aliases and functions for common git operations:

| Alias | Command |
| ------- | --------- |
| `g` | `git` |
| `ga` | `git add` |
| `gaa` | `git add --all` |
| `gc` | `git commit` |
| `gcm` | `git commit -m` |
| `gco` | `git checkout` |
| `gd` | `git diff` |
| `gl` | `git pull` |
| `gp` | `git push` |
| `gst` | `git status` |
| `glog` | `git log --oneline --decorate --graph` |

Full alias list: `alias | grep git`

### zsh-autosuggestions

- Suggestions appear in grey as you type
- Press `→` (right arrow) or `End` to accept the full suggestion
- Press `Ctrl+→` to accept the next word only
- Press `Ctrl+Space` to accept suggestion without executing

---

## 8. Final ~/.zshrc Reference

```bash
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# p10k instant prompt (keep near top of ~/.zshrc)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Load p10k config
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
```

> **Tip:** The instant prompt block should be at the very top of `~/.zshrc` — the `p10k configure` wizard places it there automatically.

---

## 9. Troubleshooting

| Issue | Fix |
| ------- | ----- |
| Icons show as boxes or `?` | Install MesloLGS NF font and set it in your terminal |
| `p10k configure` not found | Confirm `ZSH_THEME="powerlevel10k/powerlevel10k"` and `source ~/.zshrc` |
| Autosuggestions not appearing | Check plugin is in the `plugins=()` list and reload shell |
| Shell not changed after `chsh` | Log out fully; SSH sessions need reconnect |
| Slow startup | Enable p10k instant prompt (wizard option, or add the block manually) |
